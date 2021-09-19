// LauLAN.ks - Launch into LAN script
// Copyright © 2021 V. Quetschke
// Version 0.2, 08/16/2021
@LAZYGLOBAL OFF.

// Launch into target orbit with given LAN. Default setting is Minmus inclination and LAN.

// Note: This scribt needs an external library from:
//       https://github.com/KSP-KOS/KSLib.
// Place https://github.com/KSP-KOS/KSLib/blob/master/library/lib_num_to_formatted_str.ks
// into the same directory as LauLAN.ks.

// Parameters
DECLARE PARAMETER targetAltkm is 80,
    targetIncl is 6,
    lauLAN IS 78.   // Default is Minmus (80, 6, 78)

// Store current IPU value.
LOCAL myIPU TO CONFIG:IPU.
SET CONFIG:IPU TO 2000. // Makes the timing a little better.

// Load some libraries
RUNONCEPATH("libcommon").
RUNONCEPATH("lib_num_to_formatted_str").

// Controls triggers
LOCAL runLauLAN to true.

LOCAL targetAlt TO targetAltkm*1000.
LOCAL lauEarly TO 60. // Launch 60 seconds earlier than the predicted time.

CLEARSCREEN.
PRINT " Execute launch into LAN script".
PRINT " +--------------------------------------+ ".
PRINT " | LAN:                                 | ".
PRINT " | Target Incl.:                        | ".
PRINT " | Target orbit:                        | ".
PRINT " | Launch into:                         | ". // AN/DN
PRINT " | Launch time:                         | ".
PRINT " | Time now:                            | ".
PRINT " | Time to burn:                        | ".
PRINT " +--------------------------------------+ ".
PRINT " ".
PRINT " ".

// This is deviation in degrees to the AN at the current time.
// Kerbin rotates 1 deg per minute.
LOCAL laudeg TO lauLAN - (SHIP:LONGITUDE+90)
    - TIME:SECONDS/9203545*360
    - MOD(TIME:SECONDS,21600)/60.

// Make sure this is positive and between 0 and 360.
PRINT "Orig. launch deg: "+laudeg.
SET laudeg TO MOD(laudeg,360).
IF laudeg < 0 { SET laudeg TO laudeg+360. }
PRINT "Corr. launch deg: "+laudeg.
PRINT " ".
// The deg to AN is converted to time, taking into account that in
// 1 day = 360 minutes a little more than 360 degrees are covered because the
// day is longer than a solar day.
// Correct for sidereal day for AN
LOCAL lauminutes TO laudeg*21549.25/21600.

LOCAL ANDN TO "AN".
IF lauminutes > 180 {
    SET lauminutes TO lauminutes - 180*21549.25/21600.
    SET targetIncl TO -targetIncl.
    SET ANDN TO "DN".
    //PRINT "Launch into DN!".
} ELSE {
    //PRINT "Launch into AN!".
}

// Fill in static info
PRINT nuform(lauLAN,4,2)+" deg" at(20,2).
PRINT nuform(targetIncl,4,2)+" deg" at(20,3).
PRINT nuform(targetAltkm,4,2)+" km" at(20,4).
PRINT ANDN at(21,5).

LOCAL lautime TO lauminutes*60+TIME:SECONDS. 

PRINT time_formatting(lautime-lauEarly,0) at(20,7).

//display info
WHEN DEFINED runLauLAN then {
    PRINT time_formatting(TIME:SECONDS,0) at(20,6).
    PRINT nuform(lautime-lauEarly-TIME:SECONDS,5,0)+" s   " at(20,8).
    //PRINT nuform(KUNIVERSE:TIMEWARP:RATE,8,0)+"       " at(20,9).
	RETURN runLauLAN.  // Removes the trigger when running is false
}

SET KUNIVERSE:TIMEWARP:MODE TO "rails".
// SET KUNIVERSE:TIMEWARP:RATE TO 1000. // No, done by WARPTO.

PRINT "Warping.                                  " at (0,10).
KUNIVERSE:TIMEWARP:WARPTO(lautime-lauEarly).

// Wait for alignment and predicted time to start the burn. (Minus a physics cycle.)
// Launch lauEarly s early, 5s to get out of a WARP.
// The 0.53 correction factor was measured, but might change.
WAIT UNTIL TIME:SECONDS > lautime-lauEarly-5-0.525*KUNIVERSE:TIMEWARP:RATE.

// This cancels user initiated wrap mode. This happens for example when aa alarm clock alarm interrupts the
// WARPTO command from the script and the user starts the warp again manually.
KUNIVERSE:TIMEWARP:CANCELWARP().
PRINT "Stopping Warp ...                         " at (0,10).

// Make sure the warp has stopped
WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
PRINT "Spare seconds to launch: "+ROUND(lautime-lauEarly - TIME:SECONDS,1).

WAIT UNTIL TIME:SECONDS > lautime-lauEarly.
PRINT "Warping done.                             " at (0,10).
SET runLauLAN TO False.

RUNPATH("Ascent",targetAlt,targetIncl).
RUNPATH("CircAtAP").
RUNPATH("xm2").

SET CONFIG:IPU TO myIPU. // Restores original value.