// SetEjMN.ks - Set ejection node based on transfer window planner information.
// Copyright © 2023 V. Quetschke
// Version 0.1.1, 04/17/2023
@LAZYGLOBAL OFF.

// Creates a node at the time of the event at the ejction angle. See LauEject for more
// informantion.

// Note: This scribt needs an external library from:
//       https://github.com/KSP-KOS/KSLib.
// Place https://github.com/KSP-KOS/KSLib/blob/master/library/lib_num_to_formatted_str.ks
// into the same directory as this script.

// Parameters
DECLARE PARAMETER
    ejectAng IS 90,     // Ejection angle on launch day, as provided by Transfer Window Planer
    inDays IS 0,        // Days until ejection burn. Default is now.
    inHours IS 0,       // Plus hours until ejection burn. Default is 0.
    inMins IS 0,        // Plus minutes minutes until ejection burn. Default is 0.
    proDV IS 100,       // Prograde DV. Default is 100.
    normDV IS 0.      // Normal DV. Default is 0.

// Example:
// run SetEjMN(153,20,5,7,1211).
// Create maneuver node for an ejection angle of 153 in 20 days, 5 hours and 7 minutes
// with 1211 m/s prograde DV.

// Load some libraries
RUNONCEPATH("libcommon").
RUNONCEPATH("lib_num_to_formatted_str").

CLEARSCREEN.
PRINT "Create maneuver at ejection angle.".
PRINT "+--------------------------------------------------------+ ".
PRINT "|                                                        | ".
PRINT "|                                                        | ".
PRINT "|                                                        | ".
PRINT "|                                                        | ".
PRINT "|                                                        | ".
PRINT "|                                                        | ".
PRINT "|                                                        | ".
PRINT "+--------------------------------------------------------+ ".

// Functions
FUNCTION degRound {
    PARAMETER d. // degrees

    SET d TO MOD(d,360). // Normalize deg to [-180, 180].
    IF d > 180 { SET d TO d-360. }
    IF d < -180 { SET d TO d+360. }
    RETURN d.
}

// Sanity check
IF ejectAng < -180 OR ejectAng > 180 {
    PRINT "The ejection angle needs to be between -180 and +180 degrees.".
    PRINT " ".
    Print 1/0.
}

// Move to libcommon?
// Sidereal year is a constant, derive the rest.
LOCAL kerSideYear TO KERBIN:OBT:PERIOD. // Should be 9203544.6 s
LOCAL kerSolDayRot TO 360 + 21600/kerSideYear*360.
LOCAL kerSideDay TO 360/kerSolDayRot*21600. // Should be 21549.425 s
LOCAL deg2min TO kerSideDay/21600. // Factor to convert degrees to minutes.

LOCAL elDays TO ROUND(TIME:SECONDS/21600). // Complete days until 0:00h today. Needed below.

LOCAL ejAngT TO degRound(ejectAng-180). // The KAC ejection angle is against retrograde. KSP use prograde.

LOCAL time2node TO inDays*6*60*60+inHours*60*60+inMins*60. // Seconds to ejection node.
LOCAL NodeTime TO TIME:SECONDS+time2node. // Time of ejection burn

// Part I: Place maneuver node at ejAng at event time
// ejAng at current LONGITUDE and current time.
LOCAL ejAng TO MOD(180 - SHIP:LONGITUDE - MOD(TIME:SECONDS,21600)/60/deg2min+720,360).
//PRINT "ejAng: "+ejAng.

// Time to target time in complete siderial orbits. This maintains the global longitude.
LOCAL time2nodeS TO time2node - MOD(time2node,SHIP:ORBIT:PERIOD).

// ejAng at current LONGITUDE in the future. Propagated by complete orbits,
// i.e. the same global longitude. At 0:00h 0deg longitude is pointing retrograde, but Kerbin rotates.
LOCAL ejAngF TO MOD(180 - SHIP:LONGITUDE - MOD(TIME:SECONDS,21600)/60/deg2min + time2nodeS/kerSideYear*360+720,360). // xxx
//PRINT "ejAngF: "+ejAngF.

// The ej angle of the current longitude with respect to the prograde vector of the body decreses
// with growing time as Kerbin rotates.
// A negative ejDiff value indicates the target longitude is in the future, positive in the past.
// -ejDiff is the number of degrees from the future position of the ship to the longitude of the position
// of the ejection engle in that orbit.
LOCAL ejDiff TO degRound(ejAngT - ejAngF).

// Time to new node at ejection angle.
LOCAL time2nodeN TO -ejDiff/360*SHIP:OBT:PERIOD+time2nodeS.
//PRINT "ejDiff: "+ejDiff.
PRINT "| Ej. angle: "+ROUND(ejectAng,2)+" retro / "+ROUND(ejAngT,2)+" pro." AT(0,2).
PRINT "| Maneuver in:"+time_formatting(time2nodeN,0) AT(0,3).
PRINT "| Orbit incl.: "+ROUND(SHIP:OBT:INCLINATION,2)+" deg" AT(0,4).

// See above for the - sign explanation.
LOCAL myNode to NODE( time2nodeN+TIME:SECONDS, 0, normDV, proDV ). // Set MN
IF HASNODE {
    LOCAL HasN TO NEXTNODE.
    REMOVE HasN.
}
ADD myNode.

// Part II: Find deviation of AN/DN from EjAng-90deg
// Transfer future ejAng to now, by keeping the global longitude moving back in orbital periods.
// We assume 0:00h to avoid compensation for rotation.
LOCAL ejAngNow TO ejAngT - time2nodeS/kerSideYear*360.
//PRINT "ejAngNow: "+ejAngNow.
// Find body longitude of EjAngle.
LOCAL bLng TO (180-ejAngNow). // Body longitude
LOCAL gLng TO degRound( 90 + bLng + (elDays*21600)/kerSideYear*360). // Global longitude at 0:00h
LOCAL gDiff TO degRound(gLng-SHIP:OBT:LONGITUDEOFASCENDINGNODE).
// Target value is 90 for negative ejection inclination and -90 for positive ejection inclination.
// If gDiff > 0 then if gDiff > 90 the launch was too early.
// If gDiff < 0 then if gDiff > -90 the launch was too early.
LOCAL lauEarly TO 0.
IF gDiff > 0 {
    SET lauEarly to gDiff - 90.
} ELSE {
    SET lauEarly to gDiff - (-90).
}
PRINT "| For launch from orbit with ejection inclination only:" AT(0,6).
PRINT "| Angle diff. AN to node: "+ROUND(gDiff,1)+" deg" AT(0,7).
PRINT "| Launched early by approx. "+ROUND(lauEarly)+" min." AT(0,8).
PRINT " ".
PRINT " ".
