// land.ks - Land at target
// Copyright © 2021, 2022 V. Quetschke
// Version 0.7, 08/07/2022
@LAZYGLOBAL OFF.

// Script to land on the surface of a body.
// The script takes the following parameters:
//   landRot .. 0  Rotate the vessel with respect to north. By default the vessel orients itself so that
//                 the top is facing north. With 90 deg the top will face east.
//   WPpara  ..  True (default) = use active WP if set, False = do not use WP,  String = look for that WP.
// If the script finds a maneuver node it executes it and then continues with the landing procedure. The
// vessel waits until the estimated stopping distance is less than the remaining height to start the burn
// but because the stopping distance depends on the angle the vessel has with UP, the engines sometimes need
// to be stopped or throttled again. 

DECLARE PARAMETER
    // Additional rotation. By default the vessel orients itself so that the top is facing north.
    // With 90 deg the top will face east.
    landRot IS 0,
    WPpara IS TRUE. // True = use active WP, String = look for that WP, False = No WP.

RUNONCEPATH("libcommon").

// Some constants:
LOCAL g_Kerbin TO CONSTANT:G * KERBIN:MASS / KERBIN:RADIUS^2.
LOCAL g_body TO CONSTANT:G * BODY:MASS / BODY:RADIUS^2.

// The following parameters are used:
LOCAL V0v TO 10. // Target velocity for the end of phase 1
LOCAL tfin TO 5. // Characteristic time for final phase
// Final phase height. Assume we MaxDecel thrust to decellerate (including local gravity).
LOCAL MaxDecel to SHIP:AVAILABLETHRUST / SHIP:MASS - g_body.
LOCAL h0 TO V0v*tfin - (MaxDecel)/2*tfin^2.
IF h0 < 5 {
    SET h0 TO 10. // Very high TWRs will make h0 too small or negative.
}
LOCAL Vland TO 0.5. // Land with 0.5 m/s

// We will land burning retrograde plus small adjustments in pitch and yaw to steer the landing spot.
LOCAL pAng TO 0.
LOCAL yAng TO 0.
LOCAL maxAng TO 10. // Maximum correction angle
LOCAL ImpDR TO 0. // Overshoot from WP
LOCAL ImpLeft TO 0. // Left from WP

 // Roll correction to avoid rolling the rocket when launched. The value is calclated below.
LOCAL rollCorrection TO 0. // Calculated below, based on TopBearing

// The intention is to achieve a landing where V0v is reached at h0. Then the craft is decelerated to
// Vland to softly touch down.
// The script approaches the ground in the following phases
// 0. Find the critical angle (between down and the engine) where the vertical deceleration is 0.5 local
//    body g (TWR_local = 1.5).  
// 0a. Wait until the angle between down and the engine is XXdeg or less.
// 0b. Wait until the needed distance to reach V0v is equal to the current altitude-h0, then go full throttle.
// 1. Check if the stopDist is less than 90% the current altitude-h0. In that case throttle off until it
//    is required to throttle up again. 
//    Disabled for now: Keep the trottle so that stopDist = trueRadar-h0 until we reach -V0v.
// 2. Once the vertical speed is V0v adjust the trottle so that vertical speed is -V0v.
//    When the craft reaches 1m shut the engine off.
//
// TODO: Instead of looking at the vertical speed and vertical deceleration for the stopping distance,
// TODO: adjust the code to look also at the horizontal components.

CLEARSCREEN.
PRINT " ".
PRINT "Executing land script ...".
PRINT "landRot:"+nuform(landRot,5,1)+" deg".
PRINT "WPpara: "+WPpara.
PRINT " ".

// Trajectories
IF ADDONS:TR:AVAILABLE {
    IF ADDONS:TR:HASIMPACT {
        PRINT "Impact position is available.".
        //PRINT ADDONS:TR:IMPACTPOS.
    } ELSE {
        PRINT "Impact position is not available".
    }
} ELSE {
    PRINT "Trajectories is not available.".
}

// Find angle where rocket accel = 1.5*g0. Needs to be larger than 1 otherwise at the critical angle MaxDeclA
// will be zero.
LOCK critAng TO ARCCOS(1.5*g_body*SHIP:MASS/SHIP:AVAILABLETHRUST).
IF critAng < 45 { // This is arbitrary, check if there are other criteria.
    PRINT "Critical angle "+ROUND(critAng,2)+" < 45deg! Not enough thrust!".
    PRINT 1/0.
}

// Waypoints
LOCAL useWP TO FALSE.
LOCAL myWP TO FALSE.
LOCAL WPdist TO 0.
IF WPpara:TYPENAME = "String" {
    PRINT "Looking for "+WPpara+" ...".
    FOR w IN ALLWAYPOINTS() {
        //PRINT w:NAME.
        IF w:NAME = WPpara {
            SET myWP TO w.
            PRINT "Aiming for "+w:NAME.
            SET useWP TO TRUE.
            BREAK.
        }
    }
    IF myWP:TYPENAME = "Boolean" AND myWP = FALSE {
        PRINT "Found no matching waypoint. Abort!".
        PRINT 1/0.
    }
    SET WPdist TO ROUND(myWP:GEOPOSITION:DISTANCE).
    IF ADDONS:TR:AVAILABLE {
        ADDONS:TR:SETTARGET(myWP:GEOPOSITION).
    }
} ELSE IF WPpara:TYPENAME = "Boolean" AND WPpara = TRUE {
    PRINT "Looking for active waypoint ...".
    FOR w IN ALLWAYPOINTS() {
        //PRINT w:NAME.
        IF w:ISSELECTED {
            SET myWP TO w.
            PRINT "Aiming for "+w:NAME.
            SET useWP TO TRUE.
            BREAK.
        }
    }
    IF myWP:TYPENAME = "Boolean" AND myWP = FALSE {
        PRINT "Found no active waypoint. Abort!".
        PRINT 1/0.
    }
    SET WPdist TO ROUND(myWP:GEOPOSITION:DISTANCE).
    IF ADDONS:TR:AVAILABLE {
        ADDONS:TR:SETTARGET(myWP:GEOPOSITION).
    }
} ELSE {
    PRINT "No waypoint target selected!".
}
PRINT " ".

IF HASNODE {
    IF ALLNODES:LENGTH > 1 {
        PRINT "More than one maneuver node - please check!".
        PRINT 1/0.
    }
    PRINT " ".
    PRINT "Found landing maneuver node - will execute before initiating landing burn ...".
}

// Main
PRINT "3".
VO:PLAY(vTick).
WAIT 1. 
PRINT "2".
VO:PLAY(vTick).
WAIT 1. 
PRINT "1".
VO:PLAY(vTick).
WAIT 1. 


// Store current IPU value.
LOCAL myIPU TO CONFIG:IPU.
SET CONFIG:IPU TO 2000. // Makes the timing a little better.

// Execute maneuver to land, if needed.
IF HASNODE {
    IF ALLNODES:LENGTH > 1 {
        PRINT "More than one maneuver node - please check!".
        PRINT 1/0.
    }
    RUNPATH("xm2").
}

//RCS ON.
SAS OFF.

// Functions and LOCKs

// Wait until we point in the target direction.
FUNCTION waitSteer {
    LOCAL errorsig TO ABS(SteeringManager:ANGLEERROR) + ABS(SteeringManager:ROLLERROR) + 5. // Initialize to non zero
    LOCAL k TO 1/6. // EMA parameter, to avoid overshooting look at average.
    UNTIL errorsig < 3 {
        WAIT 0.1.
        SET errorsig TO errorsig*k + (ABS(SteeringManager:ANGLEERROR) + ABS(SteeringManager:ROLLERROR))*(1-k).
        //PRINT "Angle:       "+ROUND(eng2g0)+" - dev: "+ROUND(errorsig,1)+"      " AT(0,9).
        IF TERMINAL:INPUT:HASCHAR {
            IF TERMINAL:INPUT:GETCHAR() = TERMINAL:INPUT:DELETERIGHT {
                SET errorsig TO 0.
                PRINT "Aborted ..".
            }
        }      
    }
}

// Use function and avoid rotation when we are close to landing (pointing up) ... 
// LOCK mySteer TO ANGLEAXIS(yAng,SHIP:SRFRETROGRADE:TOPVECTOR)
                // *ANGLEAXIS(-pAng,SHIP:SRFRETROGRADE:STARVECTOR)
                // *SHIP:SRFRETROGRADE. // With pitch and yaw.
FUNCTION mySteer {
    LOCAL retro TO SHIP:SRFRETROGRADE.
    IF VANG(retro:VECTOR,-BODY:POSITION) < 5 {
        SET retro TO LOOKDIRUP(retro:VECTOR,myImpDir).
    }
    RETURN ANGLEAXIS(yAng,retro:TOPVECTOR)
                *ANGLEAXIS(-pAng,retro:STARVECTOR)
                *retro.
}
// Draw vectors - for debugging
//LOCAL vSt TO VECDRAW(V(0,0,0), { return 5*mySteer:VECTOR. }, blue,"Steer").
//SET vSt:SHOW TO True.
//LOCAL vStT TO VECDRAW(V(0,0,0), { return 3*mySteer:TOPVECTOR. }, blue,"StTop").
//SET vStT:SHOW TO True.

// Positive yaw moves nose to the right - ImpLeft positive need negatve yaw to correct
// Positive pitch raises the nose (needs minus sign in angleaxis) - ImpDR positive
// needs negative pitch to correct

// UP
LOCK myup TO -BODY:POSITION:NORMALIZED.
//LOCK myup TO BODY:UP.
// Draw vectors - for debugging
//LOCAL vup TO VECDRAW(V(0,0,0), { return 5*myup. }, green,"Up").
//SET vup:SHOW TO True.

// North
LOCK mynorth TO SHIP:NORTH:VECTOR.
// Draw vectors - for debugging
//LOCAL vnor TO VECDRAW(V(0,0,0), { return 5*mynorth. }, green,"North").
//SET vnor:SHOW TO True.

// East
LOCK myeast TO VCRS(myup,mynorth).

// TODO: Check if ADDONS:TR:IMPACTPOS is available, otherwise use SHIP:POSITION.

// Direction to impact, parallel to surface
//LOCK myImpDir TO VXCL(-BODY:POSITION, SHIP:SRFPROGRADE:VECTOR):NORMALIZED.
// Use function and remember retrograde when close to avoid flipping direction when landing.
LOCAL myImpDirCl TO FALSE.
LOCAL ImpClose TO FALSE.
FUNCTION myImpDir {
    LOCAL pro TO SHIP:SRFPROGRADE.
    IF NOT ImpClose AND ABS((ADDONS:TR:IMPACTPOS:POSITION - SHIP:GEOPOSITION:POSITION):MAG) < 500 {
        SET ImpClose TO TRUE.
        SET myImpDirCl TO pro.
        PRINT "Set ImpDir based on TR impact at "
            +ROUND(ABS((ADDONS:TR:IMPACTPOS:POSITION - SHIP:GEOPOSITION:POSITION):MAG))+"m".
    // Roll to correct for the top to face north plus possible extra rotation.
    // This is the final adjustment, right before the final touchdown burn.
    SET rollCorrection TO 180-TopBearing() + landRot.
    }
    IF ImpClose {
        SET pro TO myImpDirCl.
    }
    RETURN VXCL(-BODY:POSITION, pro:VECTOR):NORMALIZED.
}
// Draw vectors - for debugging
//LOCAL vid TO VECDRAW(V(0,0,0), { return 5*myImpDir. }, green,"ImpDir").
//SET vid:SHOW TO True.

// Vector pointing left from ImpDir, parallel to surface.
//LOCK myImpLeft TO VCRS(BODY:POSITION, SHIP:SRFPROGRADE:VECTOR):NORMALIZED.
LOCK myImpLeft TO VCRS(BODY:POSITION, myImpDir):NORMALIZED.
//LOCAL vid TO VECDRAW(V(0,0,0), { return 5*myImpLeft. }, green,"ImpLeft").
//SET vid:SHOW TO True.

// Bearing of projected top of vessel in flight. We use SHIP:SRFRETROGRADE:TOPVECTOR, but
// this is not applicable when landed. This determines the needed roll.
// Todo: This seems to be off by 180 deg, but works corretly with the intended rotation of the ship.
FUNCTION TopBearing {
    //LOCAL mytop TO SHIP:FACING:TOPVECTOR. // Roof of cockpit or probe
    // SHIP:SRFRETROGRADE:TOPVECTOR points opposite of cockpit. Add minus.
    LOCAL mytop TO -SHIP:SRFRETROGRADE:TOPVECTOR. // Roof of cockpit or probe (projected)
    // Cockpit/probe direction in the plane of north, east
    LOCAL mydorsal TO VXCL(myup,mytop).
    // The bearing of the topside of the ship with respect to north.
    RETURN ARCTAN2(VDOT(mydorsal,myeast),VDOT(mydorsal,mynorth)).
}

// Bearing of actual top of vessel.
FUNCTION TopBearingA {
    LOCAL mytop TO SHIP:FACING:TOPVECTOR. // Roof of cockpit or probe
    // Cockpit/probe direction in the plane of north, east
    LOCAL mydorsal TO VXCL(myup,mytop).
    // The bearing of the topside of the ship with respect to north.
    RETURN ARCTAN2(VDOT(mydorsal,myeast),VDOT(mydorsal,mynorth)).
}

// Enhanced altimeter
LOCAL bounds_box IS SHIP:BOUNDS. // IMPORTANT! do this up front, not in the loop.
// Distance of center to bottom
LOCAL cheight IS VDOT(-SHIP:FACING:VECTOR, bounds_box:FURTHESTCORNER(-SHIP:FACING:VECTOR)).

// TODO: Use terrainheight at impact?
FUNCTION trueRadar {
    // Annoying: bounds_box:BOTTOMALTRADAR and also SHIP:ALTITUDE - SHIP:GEOPOSITION:TERRAINHEIGHT
    // switched to (about) 0 at a few hundred meeters above Minmus. ALT:RADAR always worked, but was
    // only accurate below 10000m. Workaround:
    IF SHIP:ALTITUDE < 10000 {
        RETURN ALT:RADAR + 0.5 - cheight.
    } ELSE {
        RETURN bounds_box:BOTTOMALTRADAR + 0.5. // Some spare height.
    }
}
LOCK trueRadar2 TO bounds_box:BOTTOMALTRADAR + 0.5. // Some spare height.
//LOCK trueRadar2 TO SHIP:ALTITUDE - SHIP:GEOPOSITION:TERRAINHEIGHT.
//LOCK trueRadar2 TO ALT:RADAR + 0.5 + cheight.

// Get the angle between engine and g0. This uses the planned direction
// without pich and yaw corrections and not the actual vessel orientation.
LOCK eng2g0 TO VANG(-SHIP:SRFRETROGRADE:VECTOR,-myup) + SQRT(pAng^2+yAng^2). // Explain!!!

// TWR with full tanks for current body.
LOCAL StartTWR to SHIP:AVAILABLETHRUST / SHIP:MASS / g_body.

// Maximum deceleration at current angle. This does not factor in the
// increase for decreasing angle.
LOCK MaxDecelA to (COS(eng2g0)*SHIP:AVAILABLETHRUST / SHIP:MASS) - g_body.

// Main landing sequence


// Roll to correct for the top to face north plus possible extra rotation. With landRot = 90 == east.
// Do this here, after the maneuver node has been executed and repeat when we are on final approach.
// The 180 come from R(0,0,roll) needing this offset.
SET rollCorrection TO 180-TopBearing() + landRot.

// Steer towards mySteer and align roll to have top pointing east.
LOCK STEERING TO mySteer + R(0,0,rollCorrection).


// Set up screen output
CLEARSCREEN.
PRINT "Landing burn script".
// Show values for current body.
PRINT "g0 = "+ROUND(g_body,4)+"m/s2 on "+BODY:NAME+"   TWR_body: "+ROUND(StartTWR,2).
PRINT "Max. decel:  "+ROUND(MaxDecel,1)+" m/s2 (at 0deg) in local g: "+ROUND(MaxDecel/g_body,1)+" (negative is bad)".
PRINT "Crit angle:  "+ROUND(critAng,2)+"deg for 0.5g dec.".
PRINT "Stop speed:  "+ROUND(V0v,2)+"m/s for phase 1".
PRINT "Char. time:  "+ROUND(tfin,2)+"s for phase 2".
PRINT "Height h0:   "+ROUND(h0,2)+"m for phase 2".
PRINT "Eng.-angle:  "+ROUND(eng2g0)+"deg (xx deg) deviation".
PRINT "Altitude-h0: "+ROUND(trueRadar-h0).
PRINT " ".
PRINT "Phase 0a: (waiting for critical angle: "+ROUND(critAng,2)+")".
PRINT " ".
PRINT " ".
PRINT "Phase 0b: (waiting for Stopdist >= Altitude-h0)".
PRINT "Stopdist:    ".
PRINT " ".
PRINT "Phase 1:".
PRINT "Stopdist:    ".
PRINT "Deltadist:   ".
PRINT "VSpeed:      ".
PRINT " ".
PRINT "Phase 2:     ".
PRINT "Altitude:    ".
PRINT "Throttle:    ".
PRINT "VSpeed:      ".
PRINT "-".
PRINT "Target WP:   N/A".
PRINT "-".
PRINT "-".
PRINT "-".
PRINT "-".
PRINT "-".
PRINT "-".

// Display info
LOCAL loopTime IS TIME:SECONDS.
LOCAL runLA TO TRUE.
// EMA on diff vector. Is this needed? TR jumps somewhat.
LOCAL tarDiff TO V(0,0,0). // Starts with zero vector.
//LOCAL d_ema TO 1/25. // 0.5s

// TODO: Move text that doesn't change out of the trigger below.
WHEN defined runLA then {
    PRINT ROUND(eng2g0)+"deg ("+ROUND(VANG(SHIP:FACING:VECTOR,STEERING:VECTOR))+" deg) deviation    " AT(13,7).
    PRINT ROUND(trueRadar,1)+"m  " AT(13,8).
    PRINT ROUND(trueRadar2,1)+"m  " AT(22,8).
    PRINT "Bearing: "+ROUND(TopBearingA(),1)+"deg   " AT(40,7).
    PRINT "Cur. max decel: "+ROUND(MaxDecelA,1)+"m/s2     " AT(40,3).
    
    IF useWP {
        PRINT "Target WP:   "+myWP:NAME AT (0,26).
        //PRINT "Dist:        "+ROUND(myWP:GEOPOSITION:DISTANCE)+"     " AT (0,27). // GEOPOSITION is at 0m
        //LOCAL ImpDist TO VDOT(ADDONS:TR:IMPACTPOS:POSITION,myImpDir).  // Distance to TR impact
        LOCAL ImpDist TO VDOT(myWP:POSITION,myImpDir).  // Distance to TR impact
        PRINT "Dist:        "+ROUND(myWP:POSITION:MAG)+"m   Horiz: "+ROUND(ImpDist,1)+"m     " AT (0,27).
        // EMA for difference vector.
        //SET tarDiff TO tarDiff*d_ema + (ADDONS:TR:IMPACTPOS:POSITION - myWP:POSITION)*(1-d_ema).
        IF ADDONS:TR:HASIMPACT {
            SET tarDiff TO ADDONS:TR:IMPACTPOS:POSITION - myWP:POSITION.
            PRINT "WP to Imp:   "+ROUND(tarDiff:MAG)+"m     " AT (0,28).
            // Calculate and share with Phase 2
            //LOCAL ImpCorr TO ImpDist*(1-1/1.16).  // Fudge factor, see DecelPlot.m 1.16 for TWR 2.5
            //LOCAL ImpCorr TO ImpDist*(1-1/1.04).  // Fudge factor, see DecelPlot.m 1.04 for TWR 7.5
            LOCAL ImpCorr TO 0.  // Fudge factor, off
            SET ImpDR TO VDOT(tarDiff,myImpDir)-ImpCorr.
            SET ImpLeft TO VDOT(tarDiff,myImpLeft).
            PRINT "Downrange:   "+ROUND(ImpDR)+"m  pAng: "+ROUND(pAng,1)+"     " AT (0,29).
            PRINT "Left:        "+ROUND(ImpLeft)+"m  yAng: "+ROUND(yAng,1)+"     " AT (0,30).
        }
        PRINT "TR:          "+ADDONS:TR:HASIMPACT+"     " AT (0,31).
    } ELSE IF ADDONS:TR:HASIMPACT {
        PRINT "Impact dist: "+ROUND(ADDONS:TR:IMPACTPOS:POSITION:MAG)+"m   Horiz: "
            +ROUND(VDOT(ADDONS:TR:IMPACTPOS:POSITION,myImpDir),1)+"m     " AT (0,27).
    }
    PRINT ROUND((TIME:SECONDS-loopTime)*1000,1)+"   " AT (22,0).
    SET loopTime TO TIME:SECONDS.
    RETURN runLA.  // Removes the trigger when runLA is false
}

// Phase 0a
// Now wait until the angle between g0 and the engine is less than our critical angle value.
// Make sure the STEERING command had a chance to align the ship. This is important when timewrap is used.
UNTIL eng2g0 < MIN(45+maxAng*SQRT(2), critAng+maxAng*SQRT(2)) {
    WAIT 0.01.
}
PRINT "Phase 0a: (waiting for critical angle: "+ROUND(critAng,2)+") - done" AT(0,10).

// Stop Warp when the angle is reached
KUNIVERSE:TIMEWARP:CANCELWARP().
waitSteer().
PRINT "             Vessel alignment completed." AT(0,11).

// Maximum deceleration on body
// SHIP:MAXTHRUST - No thrust limit
// SHIP:AVAILABLETHRUST - With thrust limiter

// Stopping distance - at current engine thrust
// https://physics.info/motion-equations/ eq [3]
// Convert into a function?
LOCK stopDist TO (SHIP:VERTICALSPEED^2 - V0v^2) / (2*MaxDecelA). // MaxDecelA includes current set orientation.

// Abort if we cannot stop anymore.
IF stopDist >= (trueRadar-h0)*0.85 {
    PRINT "Not enough thrust to stop before hitting the ground. Abort!".
    PRINT "Altitude-h0: "+ROUND(trueRadar-h0)+" m".
    PRINT "Stopdist:    "+ROUND(stopDist)+" m".
    PRINT 1/0.
}

// To estimate downrange distance. Positive direction points down, g points down, but
// MaxDecelA should be negative in this frame (add a -). Also -(-v0) as down is positive.
// Expensive call ...
LOCK stopTime TO MAX(
        (SHIP:VERTICALSPEED + SQRT(SHIP:VERTICALSPEED^2 - 2*MaxDecelA*MAX(stopDist,0))) / -MaxDecelA,
        (SHIP:VERTICALSPEED - SQRT(SHIP:VERTICALSPEED^2 - 2*MaxDecelA*MAX(stopDist,0))) / -MaxDecelA).

// Stopping distance - including throttle setting - currently unused.
FUNCTION stopDiThro {
    RETURN (SHIP:VERTICALSPEED^2 - V0v^2) / (2*MaxDecelA*tset). // Include throttle
}

// Prepare the throttle
LOCAL tset TO 0.
LOCK THROTTLE TO tset.

// Phase 0b
// Wait until the needed distance to reach V0v is just larger than the current altitude-h0
// Make sure the STEERING command had a chance to align the ship. This is important when timewrap is used.
LOCAL haltwarp TO FALSE.
LOCAL cancelwarp TO FALSE.
IF useWP {
     // Assume max correction for waypoint landings. Otherwise stopDist undercounts becaude of steering.
    SET pAng TO maxAng.
}
PRINT "Stopdist:    "+ROUND(stopDist)+"m T:"+ROUND(stopTime)+"s      " AT(0,14).
UNTIL stopDist >= (trueRadar-h0)*0.99 { // Safety margin
    LOCAL sheight TO trueRadar-h0.

    // Check and stop WARP
    IF KUNIVERSE:TIMEWARP:RATE > 5 AND stopDist > sheight/2 {
        SET KUNIVERSE:TIMEWARP:RATE TO 5.
        IF haltwarp = FALSE {
            PRINT "Reduce WARP to 5.".
            SET haltwarp TO TRUE.
        }
        WAIT 0.01.
    }
    IF KUNIVERSE:TIMEWARP:RATE > 1 AND stopDist > sheight/1.4 {
        KUNIVERSE:TIMEWARP:CANCELWARP().
        IF cancelwarp = FALSE {
            PRINT "Cancel WARP.".
            SET cancelwarp TO TRUE.
        }
        WAIT 0.01.
    }

    //PRINT "Stopdist:    "+ROUND(stopDist)+"      " AT(0,14).
    PRINT "Stopdist:    "+ROUND(stopDist)+"m T:"+ROUND(stopTime)+"s      " AT(0,14).
    WAIT 0.01.
}
LOCAL burnStart IS TIME:SECONDS.

// Roll to correct for the top to face north plus possible extra rotation. Plus 90 = east.
// Do again here, before the final landing burn.
SET rollCorrection TO 180-TopBearing() + landRot.

// Phase 1
SET tset TO 1.

LOCAL VSpeed TO SHIP:VERTICALSPEED.
// Keep the trottle so that stopDist = trueRadar-h0 until we reach -V0v
UNTIL SHIP:VERTICALSPEED >= -V0v {
    SET VSpeed TO SHIP:VERTICALSPEED.

    LOCAL sheight TO trueRadar-h0.
    
    // ImpLeft positive need negatve yaw to correct
    LOCAL yLimit TO MIN((trueRadar-h0)/100, maxAng).
    IF ABS(-ImpLeft/10) > yLimit {
        SET yAng TO CHOOSE -yLimit IF ImpLeft > 0 ELSE yLimit.
    } ELSE {
        SET yAng TO -ImpLeft/10.
    }
    // ImpDR positive need negative pitch to correct
    LOCAL pLimit TO MIN((trueRadar-h0)/20, maxAng*0.66).
    IF ABS(-ImpDR/3) > pLimit {
        SET pAng TO CHOOSE -pLimit IF ImpDR > 0 ELSE pLimit.
    } ELSE {
        SET pAng TO -ImpDR/3.
    }

    // Needs tuning
    IF stopDist > sheight*0.99 { // 99% to have a small safety margin.
        SET tset TO 1.
    } ELSE IF stopDiThro() < sheight*0.9 {
        SET tset TO 0.0001. // Off, but Kerbalism doesn't like ignitions.
    }
    // The part below can be used instead of swtiching the engine on and off. It is less efficient
    // because it extends the burn time.
    //ELSE IF stopDiThro()+5 < sheight { // The 5 is there to make it conservative
    //  // Recalculate tset
    //  LOCAL newDec TO (SHIP:VERTICALSPEED^2 - V0v^2) / (2*sheight).
    //  SET tset TO (newDec+g_body)/(COS(eng2g0)*SHIP:AVAILABLETHRUST / SHIP:MASS).
    //}
    
    //PRINT "Stopdist:    "+ROUND(stopDist)+"      " AT(0,17).
    PRINT "Stopdist:    "+ROUND(stopDist)+"m T:"+ROUND(stopTime)+"s      " AT(0,17).
    PRINT "Deltadist:   "+ROUND(sheight-stopDist,2)+"      " AT(0,18).
    PRINT "VSpeed:      "+ROUND(VSpeed,1)+"      " AT(0,19).

    WAIT 0.01.
}

// Deploy landing legs
SET GEAR TO True.
SET yAng TO 0.
SET pAng TO 0.

// Phase 2
// Keep the trottle so that vertical speed is -Vland (-0.5 m/s)
UNTIL trueRadar < 0.5 {
    SET VSpeed TO SHIP:VERTICALSPEED.  // Moving up = positive vertical speed.

    // Calculate target deceleration based on v=g*t with 0.5s time constant.
    LOCAL newDec TO (-VSpeed-Vland)/0.5. // 0.5s time constant
    SET tset TO (newDec+g_body)/(COS(eng2g0)*SHIP:AVAILABLETHRUST / SHIP:MASS).
    PRINT "Altitude:    "+ROUND(trueRadar,1)+"      " AT(0,22).
    PRINT "Throttle:    "+ROUND(tset,3)+"      " AT(0,23).
    PRINT "VSpeed:      "+ROUND(VSpeed,2)+"      " AT(0,24).
}
SET tset TO 0.

PRINT "Landed!  Burn length: "+ROUND(TIME:SECONDS-burnStart,1)+"s".

//RCS OFF.
SAS ON.
UNLOCK STEERING.
LOCK THROTTLE TO 0. UNLOCK THROTTLE.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
SET runLA TO FALSE.
WAIT 0.03.

SET CONFIG:IPU TO myIPU. // Restores original value.