// LauEject.ks - Launch into inclination before ejection script
// Copyright © 2021, 2022, 2023 V. Quetschke
// Version 0.33, 04/15/2023
@LAZYGLOBAL OFF.

// Launch into target orbit with ejection angle provided by Transfer Window
// Planner. See Eve/Moho Flyby Build https://youtu.be/pvl8zILT5Wc?t=1498 (at 24:21)
// for an example.
// The launch needs to be timed so that the inclined orbit has an AN/DN that is
// 90 deg away from the ejection point so that the resulting inclination matches
// the calculated ejection inclination.

// Parameters
DECLARE PARAMETER targetAltkm is 100,
    targetIncl is 5,    // Default
    ejectAngRe IS 90,   // Ejection angle on launch day, as provided by Transfer Window Planer. Retrograde!!
    inDays IS 0,        // Days until ejection burn. Default is now.
    inHours IS 0,       // Plus hours until ejection burn. Default is 0.
    inMins IS 0,        // Plus minutes minutes until ejection burn. Default is 0.
    proDV IS 100,       // Prograde DV. Default is 100.
    normDV IS 0.        // Normal DV. Default is 0.

// Example:
// run LauEject(100,-5.5,153,20,5,7,100).
// Launch into 100km, with incl -5.5 for an ejection angle of 153 in 20 days, 5 hours and 7 minutes with
// prograde DV of 100 m/s.

// Load some libraries
RUNONCEPATH("libcommon").

LOCAL lauEarly TO 0.5. // Launch 0.5*60 seconds earlier than the predicted time.

// Sanity checks
IF targetIncl < -180 OR targetIncl > 180 {
    PRINT "The inclination needs to be between -180 and +180 degrees.".
    PRINT " ".
    Print 1/0.
}

IF ejectAngRe < -180 OR ejectAngRe > 180 {
    PRINT "The ejection angle needs to be between -180 and +180 degrees.".
    PRINT " ".
    Print 1/0.
}

// Move to libcommon?
// Sidereal year is a constant, derive the rest.
LOCAL kerSideYear TO KERBIN:OBT:PERIOD. // Should be 9203544.6 s
LOCAL kerSolDayRot TO 360 + 21600/kerSideYear*360.
LOCAL kerSideDay TO 360/kerSolDayRot*21600. // Should be 21549.425 s
// The deg to AN is converted to time, taking into account that in
// 1 (solar) day = 360 minutes a little more than 360 degrees are covered because the solar day
// day is a bit longer than a sidereal day. (approx. 1.0024deg in 1min)
LOCAL deg2min TO kerSideDay/21600. // Factor to convert degrees to minutes.

LOCAL ejAngPro TO ejectAngRe-180. // The KAC ejection angle is against retrograde. KSP use prograde.

LOCAL inSecs TO inDays*6*60*60+inHours*60*60+inMins*60. // Seconds to ejection node.
LOCAL NodeTime TO TIME:SECONDS+inSecs. // Time of ejection burn
// Increase of ejectAngRe in inDays (Sidereal orbital change)
LOCAL ejAngInc TO 360*inSecs/kerSideYear.

LOCAL now TO TIME:SECONDS.

// This is the deviation in degrees to the AN at the current time. The ejection angle is provided for the
// day of the ejection burn.
// The ejAngInc is the advancement of the ejection angle until the ejection burn, but at the same time.
// Advance the apparent ship ejection angle to the burn day.
// With -90deg we launch after the ejection angle. A positive launch inclination leads to a positive
// ejection inclination, therefore this is the AN, +90 is the DN. See also Mikes videos.
// MOD(now, 21600)/60 provides the minutes Kerbin rotated since 0:00.
// laudeg is "propagate current ej angle" - "target ej angle to AN"
LOCAL laudeg TO (180 - SHIP:LONGITUDE - MOD(now,21600)/60/deg2min +ejAngInc ) - (ejAngPro-90) .

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
PRINT nuform(ejectAngRe,4,2)+" deg" at(25,2).
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

// Now create maneuver node at ejection angle.
PRINT " ".
PRINT "Press 'delete' key to create node at ejection angle ...".
PRINT " ".
UNTIL FALSE {
    IF TERMINAL:INPUT:HASCHAR {
        IF TERMINAL:INPUT:GETCHAR() = TERMINAL:INPUT:DELETERIGHT {
            BREAK.
        }
    }
}
LOCAL NoSp TO TIMESPAN(NodeTime-TIME:SECONDS).
RUNPATH("SetEjMN",ejectAngRe, ROUND(NoSp:DAYS), NoSp:HOUR, NoSp:MINUTE, proDV, normDV).
