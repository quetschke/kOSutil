// LauLAN.ks - Launch into LAN script
// Copyright © 2021, 2023 V. Quetschke
// Version 0.3.1, 04/15/2023
@LAZYGLOBAL OFF.

// Launch into target orbit with given LAN. Default setting is Minmus inclination and LAN.

// Parameters
DECLARE PARAMETER targetAltkm is 80,
    targetIncl is 6,
    lauLAN IS 78.   // Default is Minmus (80, 6, 78)

// Load some libraries
RUNONCEPATH("libcommon").

LOCAL lauEarly TO 1. // Launch 60 seconds earlier than the predicted time.

// Sanity checks
IF targetIncl < -180 OR targetIncl > 180 {
    PRINT "The inclination needs to be between -180 and +180 degrees.".
    PRINT " ".
    Print 1/0.
}

IF lauLAN < 0 OR targetIncl > 360 {
    PRINT "The LAN needs to be between 0 and 360 degrees.".
    PRINT " ".
    Print 1/0.
}

// The deg to AN is converted to time, taking into account that in
// 1 day = 360 minutes a little more than 360 degrees are covered because the
// day is longer than a solar day. (approx. 1.0024deg in 1min)
// Correct for sidereal day for AN
LOCAL deg2min TO 21549.25/21600.

// Current global longitude
//PRINT (SHIP:LONGITUDE+90) + TIME:SECONDS/9203545*360 + MOD(TIME:SECONDS,21600)/60.
// Current global longitude - kOS version - same value
//PRINT BODY:ROTATIONANGLE + SHIP:LONGITUDE.

// BODY:ROTATIONANGLE // [0,360)
// SHIP:LONGITUDE     // [-180,180)

// This is deviation in degrees to the AN at the current time.
// Kerbin rotates 1 deg per minute.
LOCAL laudeg TO lauLAN - (SHIP:LONGITUDE+90)
    - TIME:SECONDS/9203545*360
    - MOD(TIME:SECONDS,21600)/60.

// Alternative version
//LOCAL laudeg2 TO lauLAN - BODY:ROTATIONANGLE - SHIP:LONGITUDE.

// Make sure this is positive and between 0 and 360.
SET laudeg TO MOD(laudeg,360). // This limits laudeg to (-360,360).
IF laudeg < 0 { SET laudeg TO laudeg+360. }

LOCAL lauminutes TO laudeg*deg2min.


LOCAL ANDN TO "AN".
LOCAL lauIncl TO targetIncl.
IF lauminutes > 180*21549.25/21600 + lauEarly + 0.5 {
    SET lauminutes TO lauminutes - 180*21549.25/21600.
    SET lauIncl TO -targetIncl.
    SET ANDN TO "DN".
    //PRINT "Launch into DN!".
} ELSE IF lauminutes < lauEarly + 0.5 {
    SET lauminutes TO lauminutes + 180*21549.25/21600.
    SET lauIncl TO -targetIncl.
    SET ANDN TO "DN".
    //PRINT "Launch into DN!".
} ELSE {
    //PRINT "Launch into AN!".
}

CLEARSCREEN.
PRINT " Execute launch into LAN script".
PRINT " +------------------------------------------------+ ".
PRINT " | LAN:                                           | ".
PRINT " | Target Incl.:                                  | ".
PRINT " | Target orbit:                                  | ".
PRINT " | Distance to launch:                            | ".
PRINT " | Optimal window:                                | ".
PRINT " | Time to burn:                                  | ".
PRINT " +------------------------------------------------+ ".
PRINT " ".
PRINT " ".

// Fill in static info
PRINT nuform(lauLAN,4,2)+" deg" at(25,2).
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

RUNPATH("LauIn",targetAltkm,lauIncl,lauminutes,lauEarly).
