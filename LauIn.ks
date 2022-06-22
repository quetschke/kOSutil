// LauIn.ks - Launch in number of minutes script
// Copyright © 2021, 2022 V. Quetschke
// Version 0.11, 06/26/2022
@LAZYGLOBAL OFF.

// Launch into target orbit in given number of minutes, with an optional parameter to launch a given number
// of minutes early. Default setting is in 5min, with 0 min early launch. The early launch time is to
// for the ascent when aiming for a LAN or ejection angle.

// Note: This scribt needs an external library from:
//       https://github.com/KSP-KOS/KSLib.
// Place https://github.com/KSP-KOS/KSLib/blob/master/library/lib_num_to_formatted_str.ks
// into the same directory as LauLAN.ks.

// Parameters
DECLARE PARAMETER targetAltkm IS 80,
    targetIncl IS 0,
    InMinutes IS 5,
    lauEarly IS 0.   // Default

// Store current IPU value.
LOCAL myIPU TO CONFIG:IPU.
SET CONFIG:IPU TO 2000. // Makes the timing a little better.

// Load some libraries
RUNONCEPATH("libcommon").
RUNONCEPATH("lib_num_to_formatted_str").

// Controls triggers
LOCAL runLauIn to true.

LOCAL targetAlt TO targetAltkm*1000.

CLEARSCREEN.
PRINT " Executing launch into LAN/ejection angle script".
PRINT " +----------------------------------------------+ ".
PRINT " | LAN:                                         | ".
PRINT " | Ejection angle:                              | ".
PRINT " | Target Incl.:                                | ".
PRINT " | Target orbit:                                | ".
PRINT " | Launch in:                                   | ". // AN/DN
PRINT " | Launch time:                                 | ".
PRINT " | Time now:                                    | ".
PRINT " | Time to burn:                                | ".
PRINT " +----------------------------------------------+ ".
PRINT " ".
PRINT " ".

// Factor to correct degrees to minutes, taking into account that in
// 1 day = 360 minutes a little more than 360 degrees are covered because the
// day is longer than a solar day. (approx. 1.0024deg in 1min)
LOCAL deg2min TO 21549.25/21600.
LOCAL now TO TIME:SECONDS.

// Find LAN from time to launch
LOCAL lauLAN TO BODY:ROTATIONANGLE + SHIP:LONGITUDE + InMinutes/deg2min.
SET lauLAN TO MOD(lauLAN,360). // This limits lauLAN to (-360,360).
IF lauLAN < 0 { SET lauLAN TO lauLAN+360. }
LOCAL lauLAN2 TO CHOOSE lauLAN -180 IF lauLAN > 180 ELSE lauLAN + 180.

// Find ejection angle from time to launch
LOCAL LauEject TO (180+90-SHIP:LONGITUDE) - InMinutes/deg2min - MOD(now,21600)/60*deg2min.
SET LauEject TO MOD(LauEject,360). // This limits LauEject to (-360,360).
IF LauEject < -180 { SET LauEject TO LauEject+360. }
IF LauEject > 180 { SET LauEject TO LauEject-360. }
LOCAL LauEject2 TO CHOOSE LauEject -180 IF LauEject > 0 ELSE LauEject + 180.

//PRINT (180+90-SHIP:LONGITUDE) - lauminutes/deg2min - MOD(now,21600)/60*deg2min.

// Fill in static info
PRINT nuform(lauLAN,4,2)+" / "+nuform(lauLAN2,4,2)+" deg" at(20,2).
PRINT nuform(lauEject,4,2)+" / "+nuform(LauEject2,4,2)+" deg" at(20,3).
PRINT nuform(targetIncl,4,2)+" / "+nuform(-targetIncl,4,2)+" deg" at(20,4).
PRINT nuform(targetAltkm,4,1)+" km" at(20,5).
PRINT nuform(InMinutes,4,1)+" min (-"+ROUND(lauEarly,1)+")" at(21,6).

LOCAL lautime TO (InMinutes-lauEarly)*60+TIME:SECONDS. 

PRINT time_formatting(lautime,0) at(20,7).

//display info
WHEN DEFINED runLauIn then {
    PRINT time_formatting(TIME:SECONDS,0) at(20,8).
    PRINT nuform(lautime-TIME:SECONDS,5,0)+" s   " at(20,9).
    //PRINT nuform(KUNIVERSE:TIMEWARP:RATE,8,0)+"       " at(20,9).
	RETURN runLauIn.  // Removes the trigger when running is false
}

SET KUNIVERSE:TIMEWARP:MODE TO "rails".
// SET KUNIVERSE:TIMEWARP:RATE TO 1000. // No, done by WARPTO.

PRINT "Warping.                                  " at (0,11).
KUNIVERSE:TIMEWARP:WARPTO(lautime).

// Wait for alignment and predicted time to start the burn. (Minus a physics cycle.)
// Allow 8s plus a correction to get out of a WARP.
// The 0.53 correction factor was measured, but might change.
WAIT UNTIL TIME:SECONDS > lautime-8-0.525*KUNIVERSE:TIMEWARP:RATE.

// This cancels user initiated wrap mode. This happens for example when aa alarm clock alarm interrupts the
// WARPTO command from the script and the user starts the warp again manually.
KUNIVERSE:TIMEWARP:CANCELWARP().
PRINT "Stopping Warp ...                         " at (0,11).

// Make sure the warp has stopped
WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
PRINT "Spare seconds to launch: "+ROUND(lautime+WarpStopTime-TIME:SECONDS,1).

WAIT UNTIL TIME:SECONDS > lautime.
PRINT "Warping done.                             " at (0,11).
SET runLauIn TO False.

RUNPATH("Ascent",targetAlt,targetIncl).
RUNPATH("CircAtAP").
RUNPATH("xm2").

SET CONFIG:IPU TO myIPU. // Restores original value.