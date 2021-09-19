// land.ks - Land at target
// Copyright © 2021 V. Quetschke
// Version 0.3, 09/19/2021
@LAZYGLOBAL OFF.

// Script to land on the surface of a body.
// The script takes no parameters.
// If the script finds a maneuver node it executes it and then continues with the landing procedure. The
// vessel waits until the estimated stopping distance is less than the remaining height to start the burn
// but because the stopping distance depends on the angle the vessel has with UP, the engines sometimes need
// to be stopped or throttled again. 
//
// The following parameters are used:
LOCAL V0v TO 10. // Target velocity for the end of phase 1
LOCAL fDec TO 2.5. // Minimum deceleration in final phase (= g_Kerbin/4)
LOCAL tfin TO 5. // Characteristic time for final phase
LOCAL h0 TO V0v*tfin - fDec/2*tfin^2. // Final phase height.
LOCAL Vland TO 1.5. // Land with 2 m/s
//
// The intention is to acheive a landing where V0v is reached at h0. Then the craft is decelerated to
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

// TODO: Instead of looking at the vertical speed and vertical deceleration for the stopping distance,
// TODO: adjust the code to look also at the horizontal components.


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

RCS ON. SAS OFF.
LOCK STEERING TO SHIP:SRFRETROGRADE.

// Forward direction. - Should be same as SHIP:SRFRETROGRADE
LOCK myforward TO SHIP:FACING:VECTOR.
// Draw vectors - for debugging
//LOCAL vforward TO VECDRAW(V(0,0,0), { return 5*myforward. }, blue,"Forward").
//SET vforward:SHOW TO True.

// UP
LOCK myup TO -BODY:POSITION:NORMALIZED.
//LOCK myup TO BODY:UP.
// Draw vectors - for debugging
//LOCAL vup TO VECDRAW(V(0,0,0), { return 5*myup. }, green,"Up").
//SET vup:SHOW TO True.

LOCAL bounds_box IS SHIP:BOUNDS. // IMPORTANT! do this up front, not in the loop.
LOCK trueRadar TO bounds_box:BOTTOMALTRADAR + 0.5. // Some spare height.

LOCAL g_body TO CONSTANT:G * BODY:MASS / BODY:RADIUS^2.

// Get the angle between engine and g0.
LOCK eng2g0 TO VANG(-myforward,-myup).

// Find angle where rocket accel = 1.5*g0
LOCAL critAng TO ARCCOS(1.5*g_body*SHIP:MASS/SHIP:AVAILABLETHRUST).
IF critAng < 60 {
    PRINT "Critical angle "+ROUND(critAng,2)+" < 60deg! Not enough thrust!".
    PRINT 1/0.
}

// This is negative for tangential trajectories (orbit)
LOCAL MaxDecel to SHIP:AVAILABLETHRUST / SHIP:MASS - g_body.

// Maximum deceleration at current angle
LOCK MaxDecelA to (COS(eng2g0)*SHIP:AVAILABLETHRUST / SHIP:MASS) - g_body.

// Set up screen output
CLEARSCREEN.
PRINT "Distance to ground: "+ROUND(trueRadar,1).
PRINT "g0 = "+ROUND(g_body,4)+"m/s2 on "+BODY:NAME. // Use this to have the correct value for other bodies.
PRINT "Max. decel:  "+ROUND(MaxDecel,4)+"m/s2 (at 0deg) in local g: "+ROUND(MaxDecel/g_body,1)+" (negative is bad)".
PRINT "Crit angle:  "+ROUND(critAng,2)+"deg".
PRINT "Stop speed:  "+ROUND(V0v,2)+"m/s for phase 1".
PRINT "Char. time:  "+ROUND(tfin,2)+"s for phase 2".
PRINT "Height h0:   "+ROUND(h0,2)+"m for phase 2".
PRINT " ".
PRINT "Phase 0a: (waiting for critical angle: "+ROUND(critAng,2)+")".
PRINT "Altitude:    "+ROUND(trueRadar).
PRINT "Angle:       "+ROUND(eng2g0).
PRINT " ".
PRINT "Phase 0b: (waiting for Stopdist <= Altitude-h0)".
PRINT "Altitude-h0: ".
PRINT "Stopdist:    ".
PRINT "Angle:       ".
PRINT " ".
PRINT "Phase 1:".
PRINT "Altitude-h0: ".
PRINT "Stopdist:    ".
PRINT "Deltadist:   ".
PRINT "Angle:       ".
PRINT "VSpeed:      ".
PRINT " ".
PRINT "Phase 2:     ".
PRINT "Altitude:    ".
PRINT "Throttle:    ".
PRINT "VSpeed:      ".
PRINT "-".

// Wait until we point in the right direction.
LOCAL errorsig TO ABS(SteeringManager:ANGLEERROR) + ABS(SteeringManager:ROLLERROR).
LOCAL k TO 1/6. // EMA parameter
UNTIL errorsig < 1 {
    WAIT 0.1.
    SET errorsig TO errorsig*k + (ABS(SteeringManager:ANGLEERROR) + ABS(SteeringManager:ROLLERROR))*(1-k).
    PRINT "Angle:       "+ROUND(eng2g0)+" - dev: "+ROUND(errorsig,3)+"      " AT(0,10).
    IF TERMINAL:INPUT:HASCHAR {
        IF TERMINAL:INPUT:GETCHAR() = TERMINAL:INPUT:DELETERIGHT {
            SET errorsig TO 0.
            PRINT "Aborted ..".
        }
    }      
}

// Phase 0a
// Now wait until the angle between g0 and the engine is less than our critical angle value.
// Make sure the STEERING command had a chance to align the ship. This is important when timewrap is used.
UNTIL eng2g0 < critAng AND VANG(SHIP:FACING:VECTOR,STEERING:VECTOR) <  1 {
    PRINT "Altitude:   "+ROUND(trueRadar)+"      " AT(0,9).
    PRINT "Angle:      "+ROUND(eng2g0)+"                             " AT(0,10).
    WAIT 0.01.
}

// Maximum deceleration on body
// SHIP:MAXTHRUST - No thrust limit
// SHIP:AVAILABLETHRUST - With thrust limiter

// Stopping distance - at current engine thrust
// https://physics.info/motion-equations/ eq [3]
// Convert into a function?
LOCK stopDist TO (SHIP:VERTICALSPEED^2 - V0v^2) / (2*MaxDecelA). // MaxDecelA includes orientation.

// Stopping distance - including throttle setting.
FUNCTION stopDiThro {
    RETURN (SHIP:VERTICALSPEED^2 - V0v^2) / (2*MaxDecelA*tset). // Include throttle
}


// Prepare the throttle
LOCAL tset TO 0.
LOCK THROTTLE TO tset.

// Phase 0b
// Wait until the needed distance to reach V0v is just larger than the current altitude-h0
// Make sure the STEERING command had a chance to align the ship. This is important when timewrap is used.
UNTIL stopDist >= trueRadar-h0 AND VANG(SHIP:FACING:VECTOR,STEERING:VECTOR) <  1 {
    PRINT "Altitude-h0: "+ROUND(trueRadar)+"      " AT(0,13).
    PRINT "Stopdist:    "+ROUND(stopDist)+"      " AT(0,14).
    PRINT "Angle:       "+ROUND(eng2g0)+"      " AT(0,15).
    WAIT 0.01.
}

// Phase 1
SET tset TO 1.

LOCAL VSpeed TO SHIP:VERTICALSPEED.
// Keep the trottle so that stopDist = trueRadar-h0 until we reach -V0v
UNTIL SHIP:VERTICALSPEED >= -V0v {
    SET VSpeed TO SHIP:VERTICALSPEED.

    LOCAL sheight TO trueRadar-h0.
    // Needs tuning
    IF stopDist > sheight {
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
    
    PRINT "Altitude-h0: "+ROUND(trueRadar-h0)+"      " AT(0,18).
    PRINT "Stopdist:    "+ROUND(stopDist)+"      " AT(0,19).
    PRINT "Deltadist:   "+ROUND(sheight-stopDist,2)+"      " AT(0,20).
    PRINT "Angle:       "+ROUND(eng2g0)+"      " AT(0,21).
    PRINT "VSpeed:      "+ROUND(VSpeed,1)+"      " AT(0,22).

    WAIT 0.01.
}

// Deploy landing legs
SET GEAR TO True.

// Phase 2
// Keep the trottle so that vertical speed is -Vland (1.5 m/s)
UNTIL trueRadar < 1 {
    SET VSpeed TO SHIP:VERTICALSPEED.

    LOCAL newDec TO (-VSpeed-Vland)/0.5. // 0.5s time constant
    SET tset TO (newDec+g_body)/(COS(eng2g0)*SHIP:AVAILABLETHRUST / SHIP:MASS).
    PRINT "Altitude:    "+ROUND(trueRadar)+"      " AT(0,25).
    PRINT "Throttle:    "+ROUND(tset,3)+"      " AT(0,26).
    PRINT "VSpeed:      "+ROUND(VSpeed,1)+"      " AT(0,27).
}
SET tset TO 0.

PRINT "Landed!".
RCS OFF. SAS ON.
UNLOCK STEERING.
LOCK THROTTLE TO 0. UNLOCK THROTTLE.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

SET CONFIG:IPU TO myIPU. // Restores original value.