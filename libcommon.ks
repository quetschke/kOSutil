// libcommon.ks - Helper library
// Copyright © 2021 V. Quetschke
// Version 0.1, 05/16/2021

// Shared subroutines for use with kOSutil 

// Use with "RUNONCEPATH("libcommon")." to avoid dupplication in memory

// Create formatted string from number.
// This function was inspired by the padding() function from
// https://github.com/KSP-KOS/KSLib/blob/master/library/lib_num_to_formatted_str.ks
FUNCTION nuform {
    PARAMETER num,  // Number
        lead,       // Number of characters before the decimal point.
                    // This includes the "-" sign.
        precision.  // Number is rounded and padded with "0" to this length
                    // of the fractional part. 
      
    LOCAL nustr IS ROUND(num,precision):TOSTRING.

    IF precision > 0 {
        IF NOT nustr:CONTAINS(".") {
            SET nustr TO nustr + ".0".
        }
        UNTIL nustr:SPLIT(".")[1]:LENGTH >= precision { SET nustr TO nustr + "0". }
        // Add leading spaces
        UNTIL nustr:SPLIT(".")[0]:LENGTH >= lead { SET nustr TO " " + nustr. }
    } ELSE {
        UNTIL nustr:LENGTH >= lead { SET nustr TO " " + nustr. }
    }
    RETURN nustr.
}


// Some beeping ..
GLOBAL VO TO getVoice(0).
GLOBAL vTick TO NOTE(480, 0.1).
GLOBAL vTakeOff TO NOTE(720, 0.5).
// Use
// VO:PLAY(vTick).

