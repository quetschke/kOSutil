// Ascent.ks - Ascent script
// Copyright © 2021, 2022, 2023 V. Quetschke
// Version 0.44 - 03/19/2023
@LAZYGLOBAL OFF.

DECLARE PARAMETER
    targetAlt is 100000,
    targetIncl is 0. // Positive Incl implies launch into ascending node, negative decending

RUNONCEPATH("libcommon").

CLEARSCREEN.
PRINT " Ascent script".
PRINT " +--------------------------------------------------+ ".
PRINT " | Inclination:                                     | ".
PRINT " | Target Incl.:                                    | ".
PRINT " | Innertial azi.:                                  | ".
PRINT " | Azi. corr.:                                      | ".
PRINT " | Pitch angle:                                     | ".
PRINT " | Angle of Att.:                                   | ".
PRINT " +--------------------------------------------------+ ".
PRINT " ".

LOCAL launchAlt TO ALT:RADAR. // Altitude at launch

LOCAL lBody TO BODY:NAME. // Local body we launch from.

// Some local variables
LOCAL actualTurnStart to 1000. // Starting height for the turn.
LOCAL turnStartVel to 100.     // Minimum velocity for the turn.
LOCAL turnEnd to 60000. // Kerbin
LOCAL turnShapeExponent to 0.4.
LOCAL maxAAttack TO 5.  // Limit the maximum angle of attack

// Parameter for other bodies.
IF lBody:STARTSWITH("Mu") {
    SET actualTurnStart to 10. // Starting height for the turn.
    SET turnStartVel to 5.     // Minimum velocity for the turn.
    SET turnEnd to 10000. // Mun
    SET turnShapeExponent to 0.2.
    SET maxAAttack TO 45.
}
ELSE IF lBody:STARTSWITH("Mi") {
    SET actualTurnStart to 10. // Starting height for the turn.
    SET turnStartVel to 5.     // Minimum velocity for the turn.
    SET turnEnd to 8000. // Minmus
    SET turnShapeExponent to 0.2.
}
ELSE IF lBody:STARTSWITH("Du") {
    SET actualTurnStart to 300. // Starting height for the turn.
    SET turnStartVel to 35.     // Minimum velocity for the turn.
    SET turnEnd to 50000. // Duna
    SET turnShapeExponent to 0.6.
    SET maxAAttack TO 45.
    PRINT "Duna".
}
ELSE IF lBody:STARTSWITH("Ike") {
    SET actualTurnStart to 10. // Starting height for the turn.
    SET turnStartVel to 5.     // Minimum velocity for the turn.
    SET turnEnd to 20000. // Ike
    SET turnShapeExponent to 0.2.
    PRINT "Ike".
}
ELSE IF lBody:STARTSWITH("Ev") {
    SET actualTurnStart to 35000. // Starting height for the turn.
    SET launchAlt TO 0.           // Assume we launched at 0 for hoverlaunch
    SET turnStartVel to 35.     // Minimum velocity for the turn.
    SET turnEnd to 45000. // Eve
    SET turnShapeExponent to 0.2.
    SET maxAAttack TO 45.
    PRINT "Eve".
}

 // Roll correction to avoid rolling the rocket when launched. The value is calclated below.
LOCAL rollCorrection TO 0. // Calculated below, based on TopBearing

// Some useful directions
LOCAL myup TO -BODY:POSITION:NORMALIZED.
LOCAL mynorth TO SHIP:NORTH:VECTOR.
LOCAL myeast TO VCRS(myup,mynorth).
LOCAL mytop TO SHIP:FACING:TOPVECTOR. // Roof of cockpit or probe
// Cockpit/probe direction in the plane of north, east
LOCAL mydorsal TO VXCL(myup,mytop).
// The bearing of the topside of the ship with respect to north.
LOCAL TopBearing TO ARCTAN2(VDOT(mydorsal,myeast),VDOT(mydorsal,mynorth)).
// This angle is used to avoid rolling of the vessel upon launch.

// Use positive inclinations only
LOCAL ANDN IS 1.
LOCAL ANDNtxt IS "AN".
IF targetIncl < 0 {
    SET ANDN TO -1.
    SET ANDNtxt TO "DN".
    SET targetIncl TO -targetIncl.
}

// Controls triggers
LOCAL runAscent to true.

// Some constants
// The horizontal velocity when the burn ends determines the azimuth adjustment.
// Make sure this velocity is reached as horizontal orbital velocity before the burn ends.
// Note, If TWR is too high, the apoapsis can be reached without reaching the horizontal
// velocity to achieve the target inclination.
//LOCAL orbVel IS 1500.0. // Kerbin
// Set according to body, but keep 1400 on Kerbin for 80km orbit, with 57% of the orbital velocity.
LOCAL orbVel TO SQRT(BODY:MU/BODY:RADIUS+targetAlt) * 0.57.

// Launch latitude
LOCAL lauLat IS SHIP:LATITUDE.

// Body rotation velocity at launch latitude
LOCAL rotVel IS (2 * CONSTANT:Pi * BODY:RADIUS) / BODY:ROTATIONPERIOD * COS(lauLat).


// Sanity checks:
// Orbital inclination can't be less than launch latitude or greater than 180 - launch latitude
IF ABS(lauLat) < 0.1 { SET lauLat TO 0. } // Allow 0 as inclanation, we are close

IF ABS(lauLat) > targetIncl {
    PRINT "Orbital inclination cannot be smaller than launch latitude".
    PRINT "Change "+ROUND(targetIncl,2)+" to "+ROUND(ABS(lauLat),2).
    SET targetIncl TO ABS(lauLat).
    //SET x to 1/0.
}.
IF 180 - ABS(lauLat) < targetIncl {
    PRINT "Orbital inclination cannot be greater than 180 - launch latitude".
    PRINT "Change "+ROUND(targetIncl,2)+" to "+ROUND(180-ABS(lauLat),2).
    SET targetIncl TO 180 - ABS(lauLat).
    //SET x to 1/0.
}.
IF targetIncl < 0 or targetIncl > 180 {
    PRINT "Orbital inclination must be between 0 and 180 degrees".
    SET x to 1/0.
}.

// For plotting, make local.
LOCAL iAzimuth IS 0.
LOCAL corrAzi IS 0.

FUNCTION calAzi {
    PARAMETER shipLat.

    // For small latitudes this yields:
    // With Incl [0,180] -> iAzimuth = 90-Incl [90,-90]
    SET iAzimuth TO ARCSIN(MAX(MIN(COS(targetIncl)/COS(shipLat),1),-1)).
    // Descending node is the other arccos() solution
    IF ANDN < 0 {
        SET iAzimuth TO 180-iAzimuth.
    }

    LOCAL cAzimuth IS iAzimuth.

    if SHIP:ORBIT:INCLINATION < targetIncl {
        LOCAL Vrotx IS orbVel * SIN(iAzimuth) - rotVel.
        LOCAL Vroty IS orbVel * COS(iAzimuth).
        SET cAzimuth TO ARCTAN2(Vrotx, Vroty).
    }

    SET corrAzi TO cAzimuth - iAzimuth.
    RETURN cAzimuth.
}

// For screen output, make these local variables.
LOCAL aAttack IS 0.
LOCAL tPitch TO 0.

FUNCTION targetPitch {
    // Use MJs formula icluding launch altitude. Avoid negative pitches, set minimum.
    SET tPitch TO MAX(90 - (( (ALTITUDE-launchAlt-actualTurnStart)/(turnEnd-actualTurnStart))^turnShapeExponent )*90,5).

    // pitch angle - does not measure azimuth:
    LOCAL cPitch TO 90-VANG(SHIP:UP:VECTOR,SHIP:SRFPROGRADE:VECTOR).
    SET aAttack TO tPitch - cPitch.
    // Towards the end of the burn we reach another area where the angle of attach can
    // exceed the maximum again because the craft has a lot of velocity pointing up. We just
    // accept that limitation although it might not be needed anymore.
    IF aAttack > maxAAttack {
        SET tPitch TO cPitch + maxAAttack.
        SET aAttack TO maxAAttack.
    } ELSE IF aAttack < -maxAAttack {
        SET tPitch TO cPitch - maxAAttack.
        SET aAttack TO -maxAAttack.
    }

    RETURN tPitch.
}

LOCAL stageThrust TO 0. // Needed for auto-staging

LOCAL loopTime IS TIME:SECONDS.
//display info
when defined runAscent then {
    PRINT nuform(SHIP:ORBIT:INCLINATION,4,2)+" deg ("+ANDNtxt+")" at(20,2).
    PRINT nuform(targetIncl*ANDN,4,2)+" deg ("+nuform(SHIP:LATITUDE,3,1)+" deg lat.)" at(20,3).
    PRINT nuform(iAzimuth,4,4)+" deg" at(20,4).
    PRINT nuform(corrAzi,4,4)+" deg" at(20,5).
    PRINT nuform(tPitch,4,4)+" deg" at(20,6).
    PRINT nuform(aAttack,4,4)+" deg" at(20,7).

    PRINT nuform((TIME:SECONDS-loopTime)*1000,5,1) AT (22,8).
    IF MAXTHRUST > stageThrust { // Thrust grows when the fuel gets lower and the altitude gets higher
        SET stageThrust TO MAXTHRUST.
    }
    SET loopTime TO TIME:SECONDS.
    RETURN runAscent.  // Removes the trigger when running is false
}

SAS OFF.

LOCK THROTTLE TO 1.

LOCAL launchTime TO TIME:SECONDS.

// Clamps? Not a trigger!
UNTIL MAXTHRUST > 0 {
    PRINT "Pre-stage running. AVAILABLETHRUST: "+round(AVAILABLETHRUST,0)+" kN.".
    STAGE.
    UNTIL STAGE:READY { WAIT 0. }
}

// Special Duna/Ike treatment
IF lBody:STARTSWITH("Du") OR lBody:STARTSWITH("Ike") {
    AG6 ON. // Make sure solar panels are retracted. Otherwise this fails.
}

//staging
LOCAL n to 1.
LOCAL cTWR TO AVAILABLETHRUST/SHIP:MASS/CONSTANT:g0. // Kerbin TWR
PRINT "Stage "+n+" running. AVAILABLETHRUST: "+round(AVAILABLETHRUST,0)+" kN.".
PRINT "                 TWR: "+round(cTWR,2).
IF cTWR > 1.6 {
    VO:PLAY(vTick).
    PRINT "First stage TWR > 1.6. Consider adusting it.".
}
WHEN MAXTHRUST < stageThrust THEN { // No more fuel?
    if runAscent = false
        RETURN false.
    // If there are no stages left we have a problem!
    IF STAGE:NUMBER = 0 {
        PRINT "No stages left! Abort!".
        SET n TO 1/0.
    }
    STAGE.
    UNTIL STAGE:READY { WAIT 0. }
    SET cTWR TO AVAILABLETHRUST/SHIP:MASS/CONSTANT:g0.
    if MAXTHRUST > 0 {
        SET n TO n+1.
        PRINT "Stage "+n+" running. AVAILABLETHRUST: "+round(AVAILABLETHRUST,0)+" kN.".
        PRINT "                 TWR: "+round(cTWR,2).
        SET stageThrust TO MAXTHRUST.
    }
    RETURN true.
}


// Pitch up, with correct azimuth and roll
// Calculate roll correction to prevent the vessel from rolling upon launch.
// See https://youtu.be/vLcLYkUHSaQ?t=2130 for details.
// The roll = 360-heading calculation assumes the probe or capsule was not rotated in the VAB (cockpit south).
//SET rollCorrection TO 180 + 180 - calAzi(SHIP:LATITUDE).
SET rollCorrection TO 180 + TopBearing - calAzi(SHIP:LATITUDE).
LOCK STEERING TO heading(calAzi(SHIP:LATITUDE),90,rollCorrection).

WAIT UNTIL SHIP:VELOCITY:SURFACE:MAG > turnStartVel.  // Minimum speed
WAIT UNTIL ALTITUDE-launchAlt > actualTurnStart.  // Minimum altitude to start the turn
PRINT "Turn started".

// We could adjust rollCorrection dynamically to the calAzi value, but that deviation is small and gradual.
LOCK STEERING TO HEADING(calAzi(SHIP:LATITUDE),targetPitch(),rollCorrection).

// Burn until apoapsis is reached
WAIT UNTIL SHIP:APOAPSIS > targetAlt.
PRINT "Target apoapsis reached".

// Engine cutoff and clean up
LOCK THROTTLE TO 0.
LOCK STEERING TO SHIP:SRFPROGRADE. // Stops dynamic calculation, goes surface prograde.
PRINT "Engine cutoff".

// We need to wait until we clear the atmosphere before warping
PRINT " Cannot warp in atmosphere.".
UNTIL (SHIP:Q = 0)   {
    WAIT 0.01.
}
PRINT " Reached vacuum.".

// Maintain apoapsis.
LOCK STEERING TO SHIP:PROGRADE. // Go prograde.
IF SHIP:APOAPSIS < targetAlt*0.99 { // Avoid extra initions for Kerbalism!!
    PRINT "Apoapsis correction burn.".
    LOCK THROTTLE TO 0.50.
    WAIT UNTIL SHIP:APOAPSIS > targetAlt.
    LOCK THROTTLE TO 0.
    PRINT "Apoapsis corrected.".
}

UNLOCK STEERING. UNLOCK THROTTLE.
SET runAscent TO false.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
PRINT "Ascent script done.".

// Now lets circularize
// in CircAtAP


