// land.ks - Land at target
// Copyright © 2021 V. Quetschke
// Version 0.1, 08/24/2021
@LAZYGLOBAL OFF.

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

// Maximum deceleration on body
// SHIP:MAXTHRUST - No thrust limit
// SHIP:AVAILABLETHRUST - With thrust limiter

// Find angle where rocket accel = 1.5*g0
LOCAL critAng TO ARCCOS(1.5*g_body*SHIP:MASS/SHIP:AVAILABLETHRUST).

// This is negative for tangential trajectories (orbit)
LOCAL MaxDecel to SHIP:AVAILABLETHRUST / SHIP:MASS - g_body.
// Some assuption that on average the angle will be between eng2go and 0deg, hence /2.
// Attention! Doesn't work with too high vertical speed. The angle is not reducing fast enough.
LOCK MaxDecelA to (COS(eng2g0/1.01)*SHIP:AVAILABLETHRUST / SHIP:MASS) - g_body.

IF critAng < 60 {
    PRINT "Critical angle "+ROUND(critAng,2)+" < 60deg! Not enough thrust!".
    PRINT 1/0.
}

CLEARSCREEN.
PRINT "Distance to ground: "+ROUND(trueRadar,3).
PRINT "g0 = "+ROUND(g_body,4)+" on "+BODY:NAME. // Use this to have the correct value for other bodies.
PRINT "Max. decel: "+ROUND(MaxDecel,4)+"(at 0deg) in local g: "+ROUND(MaxDecel/g_body,1)+" (negative is bad)".
PRINT "Crit ang: "+ROUND(critAng,2).
PRINT " ".
PRINT " ".
PRINT " ".
PRINT " ".
PRINT " ".
PRINT " ".
PRINT " ".
PRINT " ".
PRINT "-".

// Now wait until the angle is 30 degrees (60 deg between g0 and engine)
UNTIL eng2g0 < 60 {
    PRINT "Altitude: "+ROUND(trueRadar)+"      " AT(0,5).
    PRINT "Stopdist: "+"N/A"+"      " AT(0,6).
    PRINT "Angle:    "+ROUND(eng2g0)+"      " AT(0,7).
    WAIT 0.01.
}

// Stopping distance - at current engine thrust
// https://physics.info/motion-equations/ eq [3]
LOCK stopDist TO SHIP:VERTICALSPEED^2 / (2*MaxDecelA). // MaxDecelA includes orientation.

// Well shouldn't that use MIN(xxx, 1) ?
LOCK idealthrottle to (stopDist / trueRadar).

// Wait until the needed distance to stop is just larger than the current altitude
UNTIL stopDist >= trueRadar-1 {
    PRINT "Altitude: "+ROUND(trueRadar)+"      " AT(0,5).
    PRINT "Stopdist: "+ROUND(stopDist)+"      " AT(0,6).
    PRINT "Angle:    "+ROUND(eng2g0)+"      " AT(0,7).

    WAIT 0.01.
}

LOCK THROTTLE TO idealthrottle.
UNTIL 0 {
    PRINT "Altitude: "+ROUND(trueRadar)+"      " AT(0,9).
    PRINT "Stopdist: "+ROUND(stopDist)+"      " AT(0,10).
    PRINT "Angle:    "+ROUND(eng2g0)+"      " AT(0,11).
    if SHIP:VERTICALSPEED >= 0 { BREAK. }
    if trueRadar <= 50 { SET GEAR TO True. }
}

PRINT "Landed!".
RCS OFF. SAS ON.
UNLOCK STEERING.
LOCK THROTTLE TO 0. UNLOCK THROTTLE.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

SET CONFIG:IPU TO myIPU. // Restores original value.
