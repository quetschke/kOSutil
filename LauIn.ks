// LauIn.ks - Launch in number of minutes script
// Copyright © 2021, 2022, 2023 V. Quetschke
// Version 0.15, 04/16/2023
@LAZYGLOBAL OFF.

// Launch into target orbit in given number of minutes, with an optional parameter to launch a given number
// of minutes early. Default setting is in 5min, with 0 min early launch. The early launch parameter can
// be used to to fine tune the orbit when aiming for a LAN or ejection angle.

// Note: This scribt needs an external library from:
//       https://github.com/KSP-KOS/KSLib.
// Place https://github.com/KSP-KOS/KSLib/blob/master/library/lib_num_to_formatted_str.ks
// into the same directory as this script.

// Parameters
DECLARE PARAMETER targetAltkm IS 80,
    targetIncl IS 0,
    InMinutes IS 120,
    lauEarly IS 0.   // Default

// Store current IPU value.
LOCAL myIPU TO CONFIG:IPU.
SET CONFIG:IPU TO 2000. // Makes the timing a little better.

// Load some libraries
RUNONCEPATH("libcommon").
RUNONCEPATH("lib_num_to_formatted_str").

LOCAL WarpStopTime to 3. //custom value

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

// Find ejection angle from time to launch - See LauEject with laudeg=0, solve for ejectAng.
LOCAL LauEject TO (180-SHIP:LONGITUDE+90) - InMinutes/deg2min - MOD(now,21600)/60/deg2min.
SET LauEject TO MOD(LauEject,360). // This limits LauEject to (-360,360).
IF LauEject < -180 { SET LauEject TO LauEject+360. }
IF LauEject > 180 { SET LauEject TO LauEject-360. }
LOCAL LauEject2 TO CHOOSE LauEject -180 IF LauEject > 0 ELSE LauEject + 180.

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

// Warp!
SET KUNIVERSE:TIMEWARP:MODE TO "rails".
LOCAL WarpEnd TO lautime.  // Time to end of timewarp

PRINT "Warping. Press 'delete' to abort, 'w' to restart warp.           " at (0,11).
// WARPTO controls TIMEWARP:RATE, do it manually. You cannot change the rate during WARPTO.
//KUNIVERSE:TIMEWARP:WARPTO(WarpEnd-WarpStopTime).

// Better warp stopping/restarting.
LOCAL gtime TO (WarpEnd-WarpStopTime-TIME:SECONDS).
LOCAL rtime TO 0.
// Set rate for warp so that gametime passes in 1s real time.
LOCAL qrate TO MAX(10^FLOOR(LOG10(gtime)),1). // Rounding to 10^n leads to 1s to 9.99s real time.
SET KUNIVERSE:TIMEWARP:RATE TO qrate.
WAIT UNTIL KUNIVERSE:TIMEWARP:RATE / qrate > 0.5. // Wait until the rate is mostly adjusted

UNTIL TIME:SECONDS > WarpEnd-WarpStopTime {
    SET gtime TO (WarpEnd-WarpStopTime-TIME:SECONDS). // Remaining time in game sec.
    SET rtime TO gtime/KUNIVERSE:TIMEWARP:RATE. // Remaining time in real sec.
    PRINT "Est. real time:"+nuform(rtime,5,1)+"s" at (0,12).
    PRINT "Current/target warp rate:"+nuform(KUNIVERSE:TIMEWARP:RATE,7,0)
            +"/"+nuform(qrate,7,0) at (0,13).

    // Emergency break. Someone changed warp value
    IF KUNIVERSE:TIMEWARP:RATE / qrate > 3 {
        SET KUNIVERSE:TIMEWARP:RATE TO qrate.
    }
    // Abort or restart warp
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL input TO TERMINAL:INPUT:GETCHAR().
        IF input = TERMINAL:INPUT:DELETERIGHT {
            PRINT " ".
            PRINT "Aborted LauIN.ks ..".
            PRINT " ".
            PRINT " ".
            PRINT 1/0.
        } ELSE IF input = "w" {
            // Only needed to recalculate if a long enough time passed to change qrate.
            SET qrate TO MAX(10^FLOOR(LOG10(gtime)),1).
            SET KUNIVERSE:TIMEWARP:RATE TO qrate.
            PRINT "Restarted warping. Press 'delete' to abort, 'w' to restart warp." at (0,11).
        }
    }
    IF rtime < 0.8 { // Threshold
        // Only re-calculate qrate when realtime gets to the threshold.
        SET qrate TO MAX(10^FLOOR(LOG10(gtime)),1). // For threshold < 1s, this leads to 9.9s or less.
        IF KUNIVERSE:TIMEWARP:RATE / qrate > 2 { // The WAIT UNTIL below assures this is only executed once.
            SET KUNIVERSE:TIMEWARP:RATE TO qrate.
            // Debug output
            //PRINT "qr:"+nuform(qrate,7,0)+" ra:"+nuform(KUNIVERSE:TIMEWARP:RATE,7,0)+" rt:"+nuform(rtime,5,2).
            WAIT UNTIL KUNIVERSE:TIMEWARP:RATE / qrate < 2. // Wait until the rate is mostly adjusted
        }
    }
}
PRINT "Stopped Warp ...                                                " at (0,11).

// Make sure the warp has stopped
WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
PRINT "Spare seconds to launch: "+ROUND(lautime-TIME:SECONDS,1).

WAIT UNTIL TIME:SECONDS > lautime.
PRINT "Launch!".
SET runLauIn TO False.

RUNPATH("Ascent",targetAlt,targetIncl).
RUNPATH("CircAtAP").
RUNPATH("xm2").

SET CONFIG:IPU TO myIPU. // Restores original value.