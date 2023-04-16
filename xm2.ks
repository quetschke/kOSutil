// xm2.ks - Execute maneuver node script
// Copyright © 2021, 2022, 2023 V. Quetschke
// Version 0.7.7, 04/16/2023
@LAZYGLOBAL OFF.

// Script to perform a multi-stage maneuver.
// The script takes the following parameter:
//   SRBman .. FALSE (default) - execute the maneuver assuming that all engines can be controlled with the
//             Throtte.
//             TRUE - Assume the first stage to ignite is a SRB. SRBs are ignited via staging and need a
//             stage before them. (SRBs cannot be ignited via the throttle.) Accordingly stages that
//             appear to have 0 DV must be kept to allow the next staging event to ignite the SRB.
//             Only use SRBman = FALSE if your first stage to ignite is a SRB!

DECLARE PARAMETER
    SRBman IS FALSE. // SRBman = TRUE removes the ability to stretch the burn by manipulating the throttle
                     // and does not remove empty (0 DV) stages early.

IF SRBman:TYPENAME <> "Boolean" {
    PRINT " ".
    PRINT "SRBman parameter must be of type Boolean. Abort!".
    PRINT " ".
    PRINT 1/0.
}

// Store current IPU value.
LOCAL myIPU TO CONFIG:IPU.
SET CONFIG:IPU TO 2000. // Makes the timing a little better.
// SET TERMINAL:HEIGHT TO 38. // Height to fit screen output.

// The xm2 scrip uses RCS if it is availabel. It does not enable or disable the RCS status.

// Sometimes the engines pulse when locking the throttle to 0. Maybe this prevents that.
WAIT 0.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

LOCK THROTTLE TO 0. // Making sure throttle is off
RUNONCEPATH("libcommon").

LOCAL WarpStopTime to 3. //custom value

// Time it takes to complete staging event. The time was measured and add 1/2 cycle added. Somehow the
// program is off for longer burns. Might depend on engine, burn duration or simulation load.
// Have a place for a fudge factor.
LOCAL StagingDur TO 0.58+0.01+0. // Possible fudge factor.

LOCAL MyNode to NEXTNODE.

LOCAL BurnDur TO -1. // Burn time for the delta V.
LOCAL BurnDur2 TO -1. // Burn time for half the delta V.
LOCAL TLimit TO 1. // Used to implement throttle limit for short burns
LOCAL NodedV0 to MyNode:DELTAV.
LOCAL BurnDV TO 0. // This should become the same as NodedV0, but pieced together.
LOCAL sISP TO getISP(). // Current stage ISP
LOCAL CurVDV TO 0. // Current total vacuum DV from sinfo.

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
PRINT " ".
PRINT " ".
PRINT " ".

// Remove empty stages unless the SRBman parameter is true.
UNTIL SRBman OR SHIP:STAGEDELTAV(SHIP:STAGENUM):VACUUM > 0 {
    IF SHIP:STAGENUM = 0 {
        PRINT "No stages with dV left! Abort!".
        PRINT 1/0.
    }
    PRINT "Removing stage "+SHIP:STAGENUM+" with Delta V = 0.".
    STAGE.
    UNTIL STAGE:READY { WAIT 0. }
    SET sISP TO getISP(). // Current stage ISP
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

PRINT "s: SMass EMass DMass sTWR eTWR     Ft    ISP     dV   time".
FROM {local s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
    PRINT s+":"+nuform(si[s]:SMass,3,2)+nuform(si[s]:EMass,3,2)
        +nuform(si[s]:DMass,3,2)+nuform(si[s]:sTWR,3,1)
        +nuform(si[s]:maxTWR,3,1)+nuform(si[s]:FtV,5,1)
        +nuform(si[s]:KERispV,5,1)+nuform(si[s]:Vdv,5,1)
        +nuform(si[s]:dur,5,1).
    SET CurVDV TO CurVDV+si[s]:Vdv.
}
PRINT "Ship delta v: "+ROUND(CurVDV,1)+" / "+ROUND(SHIP:DELTAV:VACUUM,1)+" (KSP)".

// Check if rocket has enough delta v for maneuver
IF MyNode:BURNVECTOR:MAG > CurVDV {
    PRINT " ".
    PRINT "Not enough delta v to complete node! Abort!".
    SET axx TO 1/0.
    PRINT " ".
}

// This part doesn't use TLimit
IF MyNode:BURNVECTOR:MAG < SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT {
    PRINT " ".
    PRINT "Single stage maneuver node!".
    SET BurnDur2 TO BurnTimeP(MASS,MyNode:BURNVECTOR:MAG/2,sISP,AVAILABLETHRUST).
    SET CanThrottle TO TRUE.
} ELSE IF MyNode:BURNVECTOR:MAG / 2 < SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT {
    PRINT " ".
    PRINT "Multi stage maneuver with more than half of the DV in the".
    PRINT "current stage!".
    SET BurnDur2 TO BurnTimeP(MASS,MyNode:BURNVECTOR:MAG/2,sISP,AVAILABLETHRUST).
} ELSE {
    LOCAL cumDV TO 0.
    LOCAL cumTi TO 0.
    PRINT " ".
    PRINT "Multi stage maneuver with less than half of the DV in the".
    PRINT "current stage!".
    LOCAL s TO STAGE:NUMBER.
    // Prediction for half the burn time:
    UNTIL cumDV > MyNode:BURNVECTOR:MAG/2 {
        IF s < 0 { SET axx TO 1/0. } // Shouldn't happen - sanity check
        LOCAL lastDV TO MyNode:BURNVECTOR:MAG/2 - cumDV.
        SET cumDV TO cumDV + si[s]:VdV.
        //PRINT lastDV.
        IF cumDV < MyNode:BURNVECTOR:MAG/2 {
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
    IF SRBman {
        SET BurnDur2 TO BurnDur2-StagingDur+0.02. // SRBs ignite on STAGE, remove the wait for StagingDur.
    }
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
    UNTIL cumDV > MyNode:BURNVECTOR:MAG {
        LOCAL lastDV TO MyNode:BURNVECTOR:MAG - cumDV.
        SET cumDV TO cumDV + si[s]:VdV.
        //PRINT lastDV.
        IF cumDV < MyNode:BURNVECTOR:MAG {
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
    IF SRBman {
        SET BurnDur TO BurnDur-StagingDur+0.02. // SRBs ignite on STAGE, remove the wait for StagingDur.
    }
}
//PRINT "NodeDV: "+ROUND(NodedV0:MAG,2)+" BurnDV: "+ROUND(BurnDV,2).
PRINT "Predicted burn duration: "+nuform(BurnDur,3,4)+"s".

// Check for too short burns and stretch burn duration to 5s, except for SRBman = TRUE.
IF BurnDur < 5 AND NOT SRBman {
    SET TLimit TO BurnDur / 5.
    SET BurnDur TO BurnDur/TLimit.
    SET BurnDur2 TO BurnDur2/TLimit.
    PRINT "Extended burn duration:  "+nuform(BurnDur,3,4)+"s".
}
PRINT " ".

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
    LOCAL delV TO MIN(MyNode:BURNVECTOR:MAG,STAGE:DELTAV:CURRENT).
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
    PRINT ROUND(MyNode:DELTAV:MAG,1)+" m/s   " at (27,3).
    PRINT ROUND(MyNode:eta - BurnDur2)+"s   " at (27,4).
    PRINT ROUND(BL,1)+"s   " at (27,5).
    PRINT ROUND(BL2,1)+"s   " at (27,6).
    PRINT ROUND((TIME:SECONDS-loopTime)*1000,1)+"   " AT (22,7).
    // Todo: When burning in atmosphere stageThrust can changed. See Ascent.ks.
    SET loopTime TO TIME:SECONDS.
    RETURN runXMN.  // Removes the trigger when runXMN is false
}

//RCS ON.
SAS OFF.
LOCK THROTTLE TO 0.
LOCK STEERING TO MyNode:DELTAV.
LOCAL NodeTime TO MyNode:TIME.

// Before warping let's point in the right direction.
// WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR,STEERING) <  1.
WAIT 0.05. // Steeringmanager needs some time to initialize.
WAIT UNTIL ABS(SteeringManager:ANGLEERROR) < 2. // We don't care about SteeringManager:ROLLERROR

// Warp!
SET KUNIVERSE:TIMEWARP:MODE TO "rails".
PRINT "Warping to maneuver node point" at (0,0).
LOCAL WarpEnd TO NodeTime-BurnDur2.  // Time to end of timewarp

PRINT "Warping. Press 'delete' to abort, 'w' to restart warp.           " at (0,8).
// WARPTO controls TIMEWARP:RATE, do it manually. You cannot change the rate during WARPTO.
//KUNIVERSE:TIMEWARP:WARPTO((WarpEnd-WarpStopTime).

// Better warp stopping/restarting.
LOCAL gtime TO (WarpEnd-WarpStopTime-TIME:SECONDS).
LOCAL rtime TO 0.
// Set rate for warp so that gametime passes in 1s real time.
LOCAL qrate TO MAX(10^FLOOR(LOG10(gtime)),1). // Rounding to 10^n leads to 1s to 9.99s real time.
SET KUNIVERSE:TIMEWARP:RATE TO qrate.
// Wait until the rate is mostly adjusted
WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED OR (KUNIVERSE:TIMEWARP:RATE / qrate > 0.5).

UNTIL TIME:SECONDS > WarpEnd-WarpStopTime {
    SET gtime TO (WarpEnd-WarpStopTime-TIME:SECONDS). // Remaining time in game sec.
    SET rtime TO gtime/KUNIVERSE:TIMEWARP:RATE. // Remaining time in real sec.
    PRINT "Est. real time:"+nuform(rtime,5,1)+"s" at (0,10).
    PRINT "Current/target warp rate:"+nuform(KUNIVERSE:TIMEWARP:RATE,7,0)
            +"/"+nuform(qrate,7,0) at (0,11).

    // Emergency break. Someone changed warp value
    IF KUNIVERSE:TIMEWARP:RATE / qrate > 3 {
        SET KUNIVERSE:TIMEWARP:RATE TO qrate.
    }
    // Abort or restart warp
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL input TO TERMINAL:INPUT:GETCHAR().
        IF input = TERMINAL:INPUT:DELETERIGHT {
            PRINT " ".
            PRINT "Aborted LauIN.ks ..".
            PRINT " ".
            PRINT " ".
            PRINT 1/0.
        } ELSE IF input = "w" {
            // Only needed to recalculate if a long enough time passed to change qrate.
            SET qrate TO MAX(10^FLOOR(LOG10(gtime)),1).
            SET KUNIVERSE:TIMEWARP:RATE TO qrate.
            PRINT "Restarted warping. Press 'delete' to abort, 'w' to restart warp." at (0,8).
        }
    }
    IF rtime < 0.8 { // Threshold
        // Only re-calculate qrate when realtime gets to the threshold.
        SET qrate TO MAX(10^FLOOR(LOG10(gtime)),1). // For threshold < 1s, this leads to 9.9s or less.
        IF KUNIVERSE:TIMEWARP:RATE / qrate > 2 { // The WAIT UNTIL below assures this is only executed once.
            SET KUNIVERSE:TIMEWARP:RATE TO qrate.
            // Wait until the rate is mostly adjusted
            WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED OR (KUNIVERSE:TIMEWARP:RATE / qrate < 2).
        }
    }
}
PRINT "Stopped Warp ...                                                " at (0,8).

// Make sure the warp has stopped
WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
PRINT "Spare seconds to node: "+ROUND(WarpEnd-TIME:SECONDS,1).
PRINT " ".

// MAXTHRUST updates based on mass and fuel left. With SRBman TRUE this is likely 0.
LOCAL stageThrust to MAXTHRUST.
LOCAL cTWR TO AVAILABLETHRUST*TLimit/SHIP:MASS/CONSTANT:g0.
PRINT "Stage "+STAGE:NUMBER+" ready. Trust: "+round(AVAILABLETHRUST*TLimit,0)+" kN "+
      "TWR: "+round(cTWR,2).
// Perform staging if needed. SRBman uses stageThrust to trigger a timed stage on ignition
// because THROTTLE doesn't work with SRBs.
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
        IF MyNode:BURNVECTOR:MAG < STAGE:DELTAV:CURRENT {
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
IF TIME:SECONDS > NodeTime-BurnDur2-0.02 {
    PRINT "Alignment took too long! Consider increasing WarpStopTime".
    PRINT "  Missed burn begin by: "+ROUND(TIME:SECONDS - (NodeTime-BurnDur2-0.02),2)+"s".
}

WAIT UNTIL TIME:SECONDS > NodeTime-BurnDur2-0.02.
LOCK THROTTLE to TLimit. // Directly after the WAIT command. PRINT takes time!
// Trigger a staging event for SRBs if needed
IF SRBman AND stageThrust = 0 { SET stageThrust TO 0.1. }

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
LOCAL NodeDV2 TO MyNode:DELTAV:MAG. // Remaining delta V
PRINT "Remaining DV at node time: "+nuform(100*NodeDV2 / NodedV0:MAG,2,2)+"%".
PRINT "Est. burn time to Node:    "+nuform(BurnDur2,2,2)+"s".
PRINT "Missed by:                 "+nuform((0.5-NodeDV2/NodedV0:MAG)*2*BurnDur2,2,2)+"s".
PRINT "Positive number means burn started early, negative means late.".

LOCAL EndTime TO 0.
// Stretch the last 1/4 second to 3 seconds, except for SRBman = TRUE.
IF NOT SRBman {
    PRINT "Waiting for 0.25s remaining burn time ...".
    WAIT UNTIL CanThrottle AND BurnTimeC() < 0.25.
    SET EndTime TO TIME:SECONDS+0.25.  // Include the 1/4 second that is stretched
    PRINT "Extend burn to 3s.".
    LOCAL TSET TO TLimit*BurnTimeC()/3.
    LOCK THROTTLE TO TSET.
    PRINT "Set throttle: "+ROUND(TSET,2).
}
PRINT " ".

// Me:
WAIT UNTIL VDOT(NodedV0, MyNode:DELTAV) < 0 .
// M. Aben:
//WAIT UNTIL VANG(NodedV0, MyNode:DELTAV) > 3.5.

LOCK THROTTLE TO 0.
IF SRBman {
    SET EndTime TO TIME:SECONDS.
    PRINT "SRB mode. Remaining maneuver DV: "+ROUND(MyNode:BURNVECTOR:MAG,1)
          +" / DV left in STAGE: "+ROUND(STAGE:DELTAV:CURRENT,1).
}
PRINT "Burn completed!".
PRINT "Actual burn time:          "+nuform(EndTime-StartTime,2,2)
      +"s ("+nuform((EndTime-StartTime)/BurnDur*100,3,2)+"%)".

//RCS OFF.
SAS ON.
UNLOCK STEERING.
LOCK THROTTLE TO 0. UNLOCK THROTTLE.
SET runXMN TO FALSE.
WAIT 0.03.
REMOVE MyNode.

SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

SET CONFIG:IPU TO myIPU. // Restores original value.