// xm2.ks - Execute maneuver node script
// Copyright © 2021 V. Quetschke
// Version 0.4, 07/18/2021
@LAZYGLOBAL OFF.
RUNONCEPATH("libcommon").

LOCAL WarpStopTime to 15. //custom value
LOCAL StagingDur TO 0.58. // Time it takes to complete staging event. (measured)

LOCAL Node to NEXTNODE.

LOCAL BurnDur2 TO -1. // Burn time for half the delta V.
LOCAL NodedV0 to Node:DELTAV.
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

SET TERMINAL:WIDTH TO 76.
SET TERMINAL:HEIGHT TO 45.
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
//   FtA     .. thrust at current position
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

IF Node:BURNVECTOR:MAG < SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT {
    PRINT " ".
    PRINT "Single stage maneuver node!".
    SET BurnDur2 TO BurnTimeP(MASS,Node:BURNVECTOR:MAG/2,sISP,AVAILABLETHRUST).
    SET CanThrottle TO TRUE.
} ELSE IF Node:BURNVECTOR:MAG / 2 < SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT {
    PRINT " ".
    PRINT "Multi stage maneuver node with more than half of the".
    PRINT "delta v in the current stage!".
    SET BurnDur2 TO BurnTimeP(MASS,Node:BURNVECTOR:MAG/2,sISP,AVAILABLETHRUST).
} ELSE {
    LOCAL cumDV TO 0.
    LOCAL cumTi TO 0.
    PRINT " ".
    PRINT "Multi stage maneuver node with less than half of delta v in".
    PRINT "the current stage!".
    LOCAL s TO STAGE:NUMBER.
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
    //SET axx TO 1/0.   
}

//SET axx TO 1/0.

// Gets the combined ISP of the currently active engines
FUNCTION getISP {
    LOCAL eList IS -999.
    LIST ENGINES in eList.
    LOCAL Fsum TO 0.
    LOCAL consum TO 0.
    FOR eng in eList {
        IF eng:IGNITION {
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
// shorter value of the two options. (Calculated for full throttle)
FUNCTION BurnTimeC {
    //PARAMETER mNode.
    LOCAL bTime to -1.
    LOCAL delV TO MIN(Node:BURNVECTOR:MAG,STAGE:DELTAV:CURRENT).
    LOCAL cMass TO MASS. // Current mass
    LOCAL eMass to cMass / (CONSTANT:E^(delV/sISP/CONSTANT:g0)).
    // checking to make sure engines haven't flamed out
    IF (AVAILABLETHRUST > 0) {
        SET bTime TO (cMass - eMass) * sISP * CONSTANT:g0 / AVAILABLETHRUST.
    } 
    RETURN bTime.        
}

// Calculate burn time for given parameters. (Calculated for full throttle)
FUNCTION BurnTimeP {
    PARAMETER cmass,    // Start mass
        delV,           // Delta V burned
        myisp,          // For ISP
        thru.           // Thrust
    LOCAL bTime to -1.
    LOCAL eMass to cMass / (CONSTANT:E^(delV/myisp/CONSTANT:g0)).
    // checking to make sure engines haven't flamed out
    IF (thru > 0) {
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

RCS ON.
SAS OFF.
SET THROTTLE TO 0.

// We need to wait until we clear the atmosphere before warping
UNTIL (SHIP:Q = 0) or (Node:ETA-BurnDur2-WarpStopTime <= 0)  {
    PRINT "Cannot warp in atmosphere." at (0,6).
    WAIT 1.
}

WAIT 1.
LOCK STEERING TO Node:DELTAV.
SET WARPMODE TO "rails".
print "Warping to maneuver node point" at (0,0).
LOCAL NodeTime TO Node:TIME.
PRINT "Warping.                                  " at (0,8).
WARPTO(NodeTime-BurnDur2-WarpStopTime). // Returns immediately, but warps ...

//staging
LOCAL stageThrust to MAXTHRUST. // MAXTHRUST updates based on mass and fuel left
LOCAL cTWR TO AVAILABLETHRUST/SHIP:MASS/CONSTANT:g0.
PRINT "Stage "+STAGE:NUMBER+" running. AVAILABLETHRUST: "+round(AVAILABLETHRUST,0)+" kN.".
PRINT "                 TWR: "+round(cTWR,2).
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
    SET THROTTLE TO 0.
	STAGE.
    UNTIL STAGE:READY { WAIT 0. }
    SET cTWR TO AVAILABLETHRUST/SHIP:MASS/CONSTANT:g0.
    SET sISP TO getISP(). // Current stage ISP
	if MAXTHRUST > 0 {
		print "Stage "+STAGE:NUMBER+" ignition. AVAILABLETHRUST: "+round(AVAILABLETHRUST,2)+" kN.".
        PRINT "                 TWR: "+round(cTWR,2).
		set stageThrust to MAXTHRUST.
        // Allow extended final burn
        IF Node:BURNVECTOR:MAG < STAGE:DELTAV:CURRENT {
            SET CanThrottle TO TRUE.
        }
        SET THROTTLE TO 1.
	} ELSE {
		print "Stage "+STAGE:NUMBER+" has no thrust. AVAILABLETHRUST: "+round(AVAILABLETHRUST,2)+" kN.".
    }
    PRINT "              Stage dur.: "+ROUND(TIME:SECONDS-stTime,2).
	RETURN true. 
}

// Wait for alignment and predicted time to start the burn.
WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR,STEERING) <  1 AND TIME:SECONDS > NodeTime-BurnDur2.
PRINT "Warping done.                             " at (0,8).

SET THROTTLE to 1.
PRINT "Set throttle to 100%".

// Just for testing. Set throttle to 66% after the node
//WAIT UNTIL TIME:SECONDS > NodeTime+1.
//SET THROTTLE TO 0.5.
//PRINT "Set throttle to 50".

// Test how close we got to NodeTime
WAIT UNTIL TIME:SECONDS > NodeTime.
LOCAL NodeDV2 TO Node:DELTAV:MAG. // Remaining delta V
PRINT "Node DV at node time: "+nuform(NodeDV2 / NodedV0:MAG,1,2).
PRINT "Est. burn time to Node: "+nuform(BurnDur2,2,2).
PRINT "Missed by:              "+nuform((1-2*Node:DELTAV:MAG/NodedV0:MAG)*BurnDur2,2,2)+"s".
PRINT "Positive number means burn started early, negative means late.".

// Stretch the last 1/4 second to 3 secondss
PRINT "Waiting for 0.25s".
WAIT UNTIL CanThrottle AND BurnTimeC() < 0.25.
PRINT "Extend burn to 3s".
LOCAL TSET TO BurnTimeC()/3.
SET THROTTLE TO TSET.
PRINT "Set throttle: "+ROUND(TSET,2).

// Me:
WAIT UNTIL VDOT(NodedV0, Node:DELTAV) < 0.
// M. Aben:
//WAIT UNTIL VANG(NodedV0, Node:DELTAV) > 3.5.

LOCK THROTTLE TO 0.
PRINT "Burn completed!".

RCS OFF.
SAS ON.
UNLOCK STEERING.
LOCK THROTTLE TO 0. UNLOCK THROTTLE.
SET runXMN TO FALSE.
WAIT 0.03.
REMOVE NODE.

SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.