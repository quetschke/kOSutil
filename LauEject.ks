// LauEject.ks - Launch into inclination before ejection script
// Copyright © 2021, 2022 V. Quetschke
// Version 0.32, 11/19/2022
@LAZYGLOBAL OFF.

// Launch into target orbit with ejection angle provided by Transfer Window
// Planner. See Eve/Moho Flyby Build https://youtu.be/pvl8zILT5Wc?t=1498 (at 24:21)
// for an example.
// The launch needs to be timed so that the inclined orbit has an AN/DN that is
// 90 deg away from the ejection point so that the resulting inclination matches
// the calculated ejection inclination.

// Parameters
DECLARE PARAMETER targetAltkm is 80,
    targetIncl is 5,    // Default
    ejectAng IS 90,     // Ejection angle on launch day, as provided by Transfer Window Planer
    inDays IS 0.        // Days until ejection burn. Default is now.

// Load some libraries
RUNONCEPATH("libcommon").

LOCAL lauEarly TO 1. // Launch 60 seconds earlier than the predicted time.

// Sanity checks
IF targetIncl < -180 OR targetIncl > 180 {
    PRINT "The inclination needs to be between -180 and +180 degrees.".
    PRINT " ".
    Print 1/0.
}

IF ejectAng < -180 OR ejectAng > 180 {
    PRINT "The ejection angle needs to be between -180 and +180 degrees.".
    PRINT " ".
    Print 1/0.
}

// The deg to AN is converted to time, taking into account that in
// 1 day = 360 minutes a little more than 360 degrees are covered because the
// day is longer than a solar day. (approx. 1.0024deg in 1min)
// Correct for sidereal day for AN
LOCAL deg2min TO 21549.25/21600.
LOCAL ejAngInc TO 360*inDays*6*60*60/9203544.6. // Increase of ejectAng in inDays (Sidereal orbital change)

LOCAL now TO TIME:SECONDS.

// This is deviation in degrees to the AN at the current time. The ejection angle is provided for the
// day of the ejection burn.
// The ejAngInc is the advancement of the ejection angle until the ejection burn. Subtract this value from the
// ejection angle for the burn day.
// With the used -90deg we launch after the ejection angle. A positive launch inclination leads to a positive
// ejection inclination, therefore this is the AN, +90 is DN. See also Mikes videos.
// MOD(now, 21600)/60 provides the minutes Kerbin rotated since 0:00.
LOCAL laudeg TO (180-SHIP:LONGITUDE) - (ejectAng-ejAngInc-90) - MOD(now,21600)/60/deg2min.

// Make sure this is positive and between 0 and 360.
SET laudeg TO MOD(laudeg,360). // This limits laudeg to (-360,360).
IF laudeg < 0 { SET laudeg TO laudeg+360. }

LOCAL lauminutes TO laudeg*deg2min.

LOCAL ANDN TO "AN".
LOCAL lauIncl TO targetIncl.
IF lauminutes > 180*deg2min + lauEarly + 0.5 {
    SET lauminutes TO lauminutes - 180*deg2min.
    SET lauIncl TO -targetIncl.
    SET ANDN TO "DN".
    //PRINT "Launch into DN!".
} ELSE IF lauminutes < lauEarly + 0.5 {
    SET lauminutes TO lauminutes + 180*deg2min.
    SET lauIncl TO -targetIncl.
    SET ANDN TO "DN".
    //PRINT "Launch into DN!".
} ELSE {
    //PRINT "Launch into AN!".
}

CLEARSCREEN.
PRINT " Execute launch into ejection angle script".
PRINT " +------------------------------------------------+ ".
PRINT " | Ejection angle:                                | ".
PRINT " | Target Incl.:                                  | ".
PRINT " | Target orbit:                                  | ".
PRINT " | Distance to launch:                            | ".
PRINT " | Optimal window:                                | ".
PRINT " | Time to burn:                                  | ".
PRINT " +------------------------------------------------+ ".
PRINT " ".
PRINT " ".

// Fill in static info
PRINT nuform(ejectAng,4,2)+" deg" at(25,2).
PRINT nuform(targetIncl,4,2)+" deg" at(25,3).
PRINT nuform(targetAltkm,4,2)+" km" at(25,4).
PRINT nuform(laudeg,4,1)+" deg @ AN" at(25,5).
PRINT nuform(lauminutes,4,1)+" min @ "+ANDN at(25,6).
PRINT nuform(lauminutes*60,5,1)+" s" at(24,7).

PRINT "Executing LauIn ...".
PRINT "3".
WAIT 1.
PRINT "2".
WAIT 1.
PRINT "1".
WAIT 1.

RUNPATH("LauIn",targetAltkm,lauIncl,lauminutes-3/60,lauEarly).
