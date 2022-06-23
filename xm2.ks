// xm2.ks - Execute maneuver node script
// Copyright © 2021, 2022 V. Quetschke
// Version 0.7.1, 06/22/2022
@LAZYGLOBAL OFF.

// Store current IPU value.
LOCAL myIPU TO CONFIG:IPU.
SET CONFIG:IPU TO 2000. // Makes the timing a little better.
// SET TERMINAL:HEIGHT TO 38. // Height to fit screen output. 

RUNONCEPATH("libcommon").

LOCAL WarpStopTime to 15. //custom value

// Time it takes to complete staging event. The time was measured and add 1/2 cycle added. Somehow the
// program is off for longer burns. Might depend on engine, burn duration or simulation load.
// Have a place for a fudge factor.
LOCAL StagingDur TO 0.58+0.01+0. // Possible fudge factor.

LOCAL Node to NEXTNODE.

LOCAL BurnDur TO -1. // Burn time for the delta V.
LOCAL BurnDur2 TO -1. // Burn time for half the delta V.
LOCAL TLimit TO 1. // Used to implement throttle limit for short burns
LOCAL NodedV0 to Node:DELTAV.
LOCAL BurnDV TO 0. // This should become the same as NodedV0, but pieced together.
LOCAL sISP TO getISP(). // Current stage ISP

LOCAL CanThrottle TO FALSE.

CLEARSCREEN.
PRINT " Execute maneuver script".
PRINT " +--------------------------------------+ ".
PRINT " | Total maneuver delta-V:              | ".
PRINT " | Rem. maneuver delta-V:               | ".
PRINT " | Time to burn:                        | ".
PRINT " | CBurnLeft:                           | ".
PRINT " | CBurnLeft (throttle):                | ".
PRINT " +--------------------------------------+ ".
PRINT " ".

// Sanity checks

// Check if rocket has enough delta v for maneuver
IF Node:BURNVECTOR:MAG > SHIP:DELTAV:CURRENT {
    PRINT "".
    PRINT "Not enough delta v to complete node! Abort!".
    SET axx TO 1/0.
}

// Remove empty stages
UNTIL SHIP:STAGEDELTAV(SHIP:STAGENUM):VACUUM > 0 {
    IF SHIP:STAGENUM = 0 {
        PRINT "No stages with dV left! Abort!".
        PRINT 1/0.
    }
    PRINT "Removing stage "+SHIP:STAGENUM+" with Delta V = 0.".
    STAGE.
    UNTIL STAGE:READY { WAIT 0. }
}

RUNPATH("sinfo"). // Get stage info
// Vessel info
LOCAL si TO stinfo().
//  returnvar[stage]:key with the following defined keys values:
//   SMass   .. startmass
//   EMass   .. endmass.
//   DMass   .. stagedmass.
//   BMass   .. fuel burned
//   sTWR    .. start TWR
//   maxTWR  .. max TWR
//   sSLT    .. start SLT (Sea level thrust)
//   maxSLT  .. max SLT
//   FtV     .. thrust in vacuum
//   FtA     .. thrust at atmospheric pressure
//   KSPispV .. ISPg0 KSP - vacuum
//   KERispV .. ISPg0 Kerbal Engineer Redux - vacuum
//   KSPispA .. ISPg0 KSP - at atmospheric pressure
//   KERispA .. ISPg0 Kerbal Engineer Redux - at atmospheric pressure
//   VdV     .. Vacuum delta V
//   AdV     .. Atmospheric delta V (see atmo parameter)
//   dur     .. burn duration
// The following key is the same for all stages:
//   ATMO    .. Atmospheric pressure used for thrust calculation

PRINT " ".
IF si:TYPENAME() = "List" {
    PRINT "Succesfully received stage info!".
} ELSE {
    PRINT "sinfo.ks failed!".
    SET axx TO 1/0.
}

PRINT "Ship delta v: "+ROUND(SHIP:DELTAV:CURRENT,1).
PRINT "s: SMass EMass DMass sTWR eTWR     Ft    ISP     dV   time".
FROM {local s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
    PRINT s+":"+nuform(si[s]:SMass,3,2)+nuform(si[s]:EMass,3,2)
        +nuform(si[s]:DMass,3,2)+nuform(si[s]:sTWR,3,1)
        +nuform(si[s]:maxTWR,3,1)+nuform(si[s]:FtV,5,1)
        +nuform(si[s]:KERispV,5,1)+nuform(si[s]:Vdv,5,1)
        +nuform(si[s]:dur,5,1).
}

// This part doesn't use TLimit
IF Node:BURNVECTOR:MAG < SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT {
    PRINT " ".
    PRINT "Single stage maneuver node!".
    SET BurnDur2 TO BurnTimeP(MASS,Node:BURNVECTOR:MAG/2,sISP,AVAILABLETHRUST).
    SET CanThrottle TO TRUE.
} ELSE IF Node:BURNVECTOR:MAG / 2 < SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT {
    PRINT " ".
    PRINT "Multi stage maneuver with more than half of the DV in the current stage!".
    SET BurnDur2 TO BurnTimeP(MASS,Node:BURNVECTOR:MAG/2,sISP,AVAILABLETHRUST).
} ELSE {
    LOCAL cumDV TO 0.
    LOCAL cumTi TO 0.
    PRINT " ".
    PRINT "Multi stage maneuver with less than half of the DV in the current stage!".
    LOCAL s TO STAGE:NUMBER.
    // Prediction for half the burn time:
    UNTIL cumDV > Node:BURNVECTOR:MAG/2 {
        IF s < 0 { SET axx TO 1/0. } // Shouldn't happen - sanity check
        LOCAL lastDV TO Node:BURNVECTOR:MAG/2 - cumDV.
        SET cumDV TO cumDV + si[s]:VdV.
        //PRINT lastDV.
        IF cumDV < Node:BURNVECTOR:MAG/2 {
            // Not the final stage
            SET cumTi TO cumTi + si[s]:dur + StagingDur.
        } ELSE {
            SET cumTi TO cumTi + BurnTimeP(si[s]:SMass,lastDV,si[s]:KERispV,si[s]:FtV).
            //PRINT "BT:".
            //PRINT BurnTimeP(si[s]:SMass,si[s]:dv,si[s]:KERispV,si[s]:Ft).
        }
        //PRINT s+" DV: "+cumDV+" time: "+cumTi.
        SET s TO s-1.
    }
    SET BurnDur2 TO cumTi.
}
// Prediction for the full burn time BurnDur for statistics and burn time debugging.
{
    // The single stage maneuver could use the stock value, but this doesn't take much time, so
    // the same method is used for all three burn types.
    LOCAL cumDV TO 0.
    LOCAL cumTi TO 0.
    LOCAL cumDVb TO 0. // Total dV in node
    LOCAL s TO STAGE:NUMBER.
    // Prediction for the burn time:
    UNTIL cumDV > Node:BURNVECTOR:MAG {
        LOCAL lastDV TO Node:BURNVECTOR:MAG - cumDV.
        SET cumDV TO cumDV + si[s]:VdV.
        //PRINT lastDV.
        IF cumDV < Node:BURNVECTOR:MAG {
            // Not the final stage
            SET cumTi TO cumTi + si[s]:dur + StagingDur.
            SET BurnDV TO cumDV.

        } ELSE {
            SET cumTi TO cumTi + BurnTimeP(si[s]:SMass,lastDV,si[s]:KERispV,si[s]:FtV).
            SET BurnDV TO BurnDV + lastDV.
            //PRINT "BT:".
            //PRINT BurnTimeP(si[s]:SMass,si[s]:dv,si[s]:KERispV,si[s]:Ft).
        }
        //PRINT s+" DV: "+BurnDV+" time: "+cumTi.
        SET s TO s-1.
    }
    SET BurnDur TO cumTi.
}
//PRINT "NodeDV: "+ROUND(NodedV0:MAG,2)+" BurnDV: "+ROUND(BurnDV,2).
PRINT "Predicted burn duration: "+nuform(BurnDur,3,4)+"s".

// Check for too short burns
IF BurnDur < 5 {
    SET TLimit TO BurnDur / 5.
    SET BurnDur TO BurnDur/TLimit.
    SET BurnDur2 TO BurnDur2/TLimit.
    PRINT "Extended burn duration:  "+nuform(BurnDur,3,4)+"s".
}

// Gets the combined ISP of the currently active engines
FUNCTION getISP {
    LOCAL eList IS -999.
    LIST ENGINES in eList.
    LOCAL Fsum TO 0.
    LOCAL consum TO 0.
    FOR eng in eList {
        IF eng:IGNITION {
            // TLimit cancels out
            SET Fsum TO Fsum + eng:AVAILABLETHRUST.
            SET consum TO consum + eng:AVAILABLETHRUST/eng:ISP.
        }
    }
    IF (consum > 0) {
        RETURN Fsum / consum.
        // returns -1 if no active engines
    } ELSE {
        RETURN -1.
    }
}

// Calculate burn time in current stage or maneuver node, and returns the
// shorter value of the two options. (Calculated for full throttle with TLimit)
FUNCTION BurnTimeC {
    //PARAMETER mNode.
    LOCAL bTime to -1.
    LOCAL delV TO MIN(Node:BURNVECTOR:MAG,STAGE:DELTAV:CURRENT).
    LOCAL cMass TO MASS. // Current mass
    LOCAL eMass to cMass / (CONSTANT:E^(delV/sISP/CONSTANT:g0)).
    // checking to make sure engines haven't flamed out
    IF (AVAILABLETHRUST > 0) {
        SET bTime TO (cMass - eMass) * sISP * CONSTANT:g0 / AVAILABLETHRUST / TLimit.
    } 
    RETURN bTime.        
}

// Calculate burn time for given parameters.
FUNCTION BurnTimeP {
    PARAMETER cMass,    // Start mass
        delV,           // Delta V burned
        myisp,          // For ISP
        thru.           // Thrust
    LOCAL bTime to -1.
    // checking to make sure engines haven't flamed out
    IF (thru > 0 and myisp > 0) {
        LOCAL eMass to cMass / (CONSTANT:E^(delV/myisp/CONSTANT:g0)).
        SET bTime TO (cMass - eMass) * myisp * CONSTANT:g0 / thru.
    } 
    RETURN bTime.        
}


//display info
LOCAL loopTime IS TIME:SECONDS.
LOCAL runXMN TO true.
WHEN defined runXMN then {
    LOCAL BL IS BurnTimeC().
    LOCAL BL2 IS CHOOSE BL/THROTTLE IF THROTTLE > 0 ELSE 0.
    PRINT ROUND(NodedV0:MAG,1)+" m/s   " at (27,2).
    PRINT ROUND(Node:DELTAV:MAG,1)+" m/s   " at (27,3).
    PRINT ROUND(Node:eta - BurnDur2)+"s   " at (27,4).
    PRINT ROUND(BL,1)+"s   " at (27,5).
    PRINT ROUND(BL2,1)+"s   " at (27,6).
    PRINT ROUND((TIME:SECONDS-loopTime)*1000,1)+"   " AT (22,7).
    SET loopTime TO TIME:SECONDS.
    RETURN runXMN.  // Removes the trigger when runXMN is false
}

RCS ON. SAS OFF.
LOCK THROTTLE TO 0.
LOCK STEERING TO Node:DELTAV.

// Before warping let's point in the right direction.
// WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR,STEERING) <  1.
WAIT 0.05. // Steeringmanager needs some time to initialize.
WAIT UNTIL ABS(SteeringManager:ANGLEERROR) + ABS(SteeringManager:ROLLERROR) < 2.

// Warp!
SET KUNIVERSE:TIMEWARP:MODE TO "rails".
PRINT "Warping to maneuver node point" at (0,0).
LOCAL NodeTime TO Node:TIME.
PRINT "Warping.                                  " at (0,8).

LOCAL BurnStart TO NodeTime-BurnDur2-WarpStopTime.
KUNIVERSE:TIMEWARP:WARPTO(BurnStart). // Returns immediately, but warps ...

// Wait for alignment and predicted time to start the burn. (Minus a physics cycle.)
// Allow 8s plus a correction to get out of a WARP.
// The 0.53 correction factor was measured, but might change.
WAIT UNTIL TIME:SECONDS > BurnStart-8-0.525*KUNIVERSE:TIMEWARP:RATE.

// This cancels user initiated wrap mode. This happens for example when aa alarm clock alarm interrupts the
// WARPTO command from the script and the user starts the warp again manually.
KUNIVERSE:TIMEWARP:CANCELWARP().
PRINT "Stopping Warp ...                         " at (0,8).

// Make sure the warp has stopped
WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
PRINT "Spare seconds to node: "+ROUND(BurnStart+WarpStopTime-TIME:SECONDS,1).

WAIT UNTIL TIME:SECONDS > BurnStart.
PRINT "Warping done.                             " at (0,8).


//staging
LOCAL stageThrust to MAXTHRUST. // MAXTHRUST updates based on mass and fuel left
LOCAL cTWR TO AVAILABLETHRUST*TLimit/SHIP:MASS/CONSTANT:g0.
PRINT "Stage "+STAGE:NUMBER+" ready. Trust: "+round(AVAILABLETHRUST*TLimit,0)+" kN "+
      "TWR: "+round(cTWR,2).
WHEN MAXTHRUST<stageThrust THEN { // No more fuel?
    if runXMN = false
        RETURN false. 
    // If there are no stages left we have a problem!
    SET CanThrottle TO FALSE.
    LOCAL stTime IS TIME:SECONDS.
    IF STAGE:NUMBER = 0 {
        PRINT "No stages left! Abort!".
        SET n TO 1/0.
    }
    // The throttle is set to zero to make the time spend with active engines in the various
    // stages more deterministic. When throttle is set back below, after the wait for
    // "STAGE:READY" this means that the "Stage dur.:" value printed below is exactly the
    // time that was spent on staging, without any thrust. This value is used for the
    // StagingDur variable.
    LOCK THROTTLE TO 0.
    STAGE.
    UNTIL STAGE:READY { WAIT 0. }
    SET cTWR TO AVAILABLETHRUST*TLimit/SHIP:MASS/CONSTANT:g0.
    SET sISP TO getISP(). // Current stage ISP
    if MAXTHRUST > 0 {
        // KOS bug
        IF SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT = 0 {
            PRINT " ".
            PRINT "KOS STAGE:DELTAV bug. There is thrust but no DV in the current stage!".
            PRINT "There likely was a stage 0 without function that was removed during".
            PRINT "staging. Remove that, and try again".
            PRINT "DV at current stage ("+SHIP:STAGENUM+"): "+SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT.
            PRINT "DV at next stage ("+(SHIP:STAGENUM-1)+"): "+SHIP:STAGEDELTAV(SHIP:STAGENUM-1):CURRENT.
            PRINT "Abort!".
            PRINT " ".
            PRINT " ".
            SET n TO 1/0.
        }
        PRINT "Stage "+STAGE:NUMBER+" ignition. Thrust: "+round(AVAILABLETHRUST*TLimit,2)+" kN  "+
              "TWR: "+round(cTWR,2).
        SET stageThrust to MAXTHRUST.
        // Allow extended final burn
        IF Node:BURNVECTOR:MAG < STAGE:DELTAV:CURRENT {
            SET CanThrottle TO TRUE.
        }
        LOCK THROTTLE TO TLimit.
    } ELSE {
        PRINT "Stage "+STAGE:NUMBER+" no thrust. Thrust: "+round(AVAILABLETHRUST*TLimit,2)+" kN.".
    }
    PRINT "              Stage dur.: "+ROUND(TIME:SECONDS-stTime,2).
    //PRINT "BurnTimeC: "+BurnTimeC().
    //PRINT "STAGE:DELTAV:CURRENT "+STAGE:DELTAV:CURRENT.
    RETURN true. 
}

// Wait for alignment and predicted time to start the burn. (Minus a physics cycle.)
WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR,STEERING) <  1.
WAIT UNTIL TIME:SECONDS > NodeTime-BurnDur2-0.02.
LOCK THROTTLE to TLimit. // Directly after the WAIT command. PRINT takes time!
LOCAL StartTime TO TIME:SECONDS.
PRINT "Deviation from ignition time: "+ROUND(StartTime-(NodeTime-BurnDur2-0.02),2).

PRINT "Warping done.                             " at (0,8).
PRINT "Set throttle to 100%".

// Just for testing. Set throttle to 66% after the node
//WAIT UNTIL TIME:SECONDS > NodeTime+1.
//LOCK THROTTLE TO 0.5.
//PRINT "Set throttle to 50".

// Measure how close we got to NodeTime
WAIT UNTIL TIME:SECONDS > NodeTime.
LOCAL NodeDV2 TO Node:DELTAV:MAG. // Remaining delta V
PRINT "Remaining DV at node time: "+nuform(100*NodeDV2 / NodedV0:MAG,2,2)+"%".
PRINT "Est. burn time to Node:    "+nuform(BurnDur2,2,2)+"s".
PRINT "Missed by:                 "+nuform((0.5-NodeDV2/NodedV0:MAG)*2*BurnDur2,2,2)+"s".
PRINT "Positive number means burn started early, negative means late.".

// Stretch the last 1/4 second to 3 secondss
PRINT "Waiting for 0.25s remaining burn time ...".
WAIT UNTIL CanThrottle AND BurnTimeC() < 0.25.
LOCAL EndTime TO TIME:SECONDS.  // Note, this is 1/4 second too early

PRINT "Extend burn to 3s.".
LOCAL TSET TO TLimit*BurnTimeC()/3.
LOCK THROTTLE TO TSET.
PRINT "Set throttle: "+ROUND(TSET,2).
PRINT " ".
PRINT "Predicted burn time:       "+nuform(BurnDur,2,2)+"s".
PRINT "Actual burn time:          "+nuform(EndTime-StartTime+0.25,2,2)
      +"s ("+nuform((EndTime-StartTime+0.25)/BurnDur*100,3,2)+"%)".
PRINT " ".


// Me:
WAIT UNTIL VDOT(NodedV0, Node:DELTAV) < 0.
// M. Aben:
//WAIT UNTIL VANG(NodedV0, Node:DELTAV) > 3.5.

LOCK THROTTLE TO 0.
PRINT "Burn completed!".

RCS OFF. SAS ON.
UNLOCK STEERING.
LOCK THROTTLE TO 0. UNLOCK THROTTLE.
SET runXMN TO FALSE.
WAIT 0.03.
REMOVE NODE.

SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

SET CONFIG:IPU TO myIPU. // Restores original value.