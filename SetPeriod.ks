// SetPeriod.ks - Create node to circularize at AP script
// Copyright © 2021 V. Quetschke
// Version 0.1, 09/02/2021
@LAZYGLOBAL OFF.

// Parameters
DECLARE PARAMETER T_t is 0*60*60+32*60+40. // Period target. Default is 32m40s

// Sanity check
IF SHIP:AVAILABLETHRUST = 0 { PRINT "No thrust! Check staging.". PRINT 1/0. }

// Store current IPU value.
LOCAL myIPU TO CONFIG:IPU.
SET CONFIG:IPU TO 2000. // Makes the timing a little better.

// Gravitational parameter of SOI body
LOCAL mu TO CONSTANT:G * SHIP:BODY:MASS.
LOCAL Pi TO CONSTANT:PI.

// Calc new semi-major axis for target period
LOCAL a_T TO (mu*(T_t/2/Pi)^2)^(1/3).

// Ship orbit
LOCAL orbi TO SHIP:ORBIT.
LOCAL T_0 TO orbi:PERIOD.

CLEARSCREEN.
PRINT "Script SetPeriod".
PRINT "Start period      : "+T_0. // Use this to have the correct value for other bodies.
PRINT "Target period     : "+T_t.
PRINT "Correction        : "+"---".
PRINT "Velocity change   : ".
PRINT "1us/Ph.Cy. throt  : ".
PRINT " ".
PRINT "Throttle          : "+"--".
PRINT "Current period    : "+T_0.
PRINT "Diff.: "+(T_0-T_t) AT(39,8).
PRINT " ".
PRINT "Final period      : ".
PRINT "Diff.: " AT(39,10).
PRINT "-".

RCS ON. SAS OFF.
LOCAL corrdir TO 1. // Prograde
IF T_0 > T_t {
    // Need do speed up/decrease orbit => retrograde
    LOCK STEERING TO SHIP:RETROGRADE.
    SET corrdir TO -1.
    PRINT "Correction        : "+"retrograde" AT(0,3).
} ELSE {
    // Need do slow down/increase orbit => prograde
    LOCK STEERING TO SHIP:PROGRADE.
    PRINT "Correction        : "+"prograde" AT(0,3).
}
WAIT 0.03. // Wait a bit to get the PID loop going.
WAIT UNTIL ABS(STEERINGMANAGER:ANGLEERROR) < 1.
PRINT "<aquired>" AT(32,3).

LOCAL starttime TO TIME:SECONDS.

// Current radius (distance to center of SOI)
LOCK radius TO SHIP:BODY:POSITION:MAG.

// Velocity difference current to target.
LOCAL dv TO (SQRT(2*mu/radius - mu/a_T) - orbi:VELOCITY:ORBIT:MAG)*corrdir.

PRINT "Velocity change   : "+dv AT(0,4).

// The ROUND removes some noise in the current period.
LOCK dT TO ABS(ROUND(orbi:PERIOD,7)-T_t). // Period deviation from target

// dv/dT*0.000001s = dv for 1us change
LOCAL dv1us TO dv/dT*0.000001.
LOCAL bu1us TO dv1us*SHIP:MASS/SHIP:AVAILABLETHRUST. // Duration for 1us period change in s.
LOCAL minthrottle TO bu1us/0.02/2. // Throttle value to change period by 1us in 1/2 physics tick
PRINT "1us/Ph.Cy. throt  : "+minthrottle AT(0,5).

// Set throttle. At a period difference of 10us we switch to minthrottle.
LOCK THROTTLE TO MAX(minthrottle*dT/10e-6, minthrottle).

// Now wait until the difference is small enough (crossing zero)
UNTIL (orbi:PERIOD - T_t) * corrdir > 0 {
    PRINT THROTTLE+"              " AT(20,7).
    PRINT orbi:PERIOD+"   " AT(20,8).
    PRINT (orbi:PERIOD-T_t)+"   " AT(46,8).
    WAIT 0.
}
LOCK THROTTLE TO 0.
PRINT "Final period      : "+orbi:PERIOD+"   Diff.: "+(orbi:PERIOD-T_t)+"   " AT(0,10).
PRINT "Burn completed!  Duration: "+ROUND(TIME:SECONDS-starttime,3).

RCS OFF. SAS ON.
UNLOCK STEERING.
UNLOCK THROTTLE.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
WAIT 0.03.

SET CONFIG:IPU TO myIPU. // Restores original value.
