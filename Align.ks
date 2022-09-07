// Align.ks - Align the craft for solar panel exposure
// Copyright © 2021, 2022 M. Aben, V. Quetschke
// Version 0.3, 06/26/2022
//
// This script is based on a version from Mike Aben in https://github.com/MikeAben64/kOS-Scripts .
// https://github.com/MikeAben64/kOS-Scripts/blob/main/align.ks
// The curent version has been extended to have additional features.
@LAZYGLOBAL OFF.

// DESCRIPTION:
// Orients vessel for ideal solar panel exposure.
// Take a parameter for the orientation of the vessel:
//  'n' - normal, nose up
//  'd' - dorsal, top up
//  'w' - wing, right side up (dorsal+90deg))
// The program watits for minimal deviation from the value set vor steering using an eponential moving
// or can be exited through pressing 'delete'.

// ***Parameter***
// Orientation of solar panels
PARAMETER orientation IS "n".

main().

// Main program
FUNCTION main {
    SAS OFF.
    IF (orientation = "d") {
        LOCK STEERING to HEADING(0, SHIP:GEOPOSITION:LAT - 90) + R(0, 0, 0).
    } ELSE IF (orientation = "w") {
        LOCK STEERING to HEADING(0, SHIP:GEOPOSITION:LAT - 90) + R(0, 0, 90).
    } ELSE {
        LOCK STEERING to HEADING(0, SHIP:GEOPOSITION:LAT) + R(0, 0, 0).
    }
    CLEARSCREEN.
    PRINT("Aligning ... Press 'delete' to abort early.").
    PRINT(" ").

    LOCAL k TO 1/6. // EMA parameter
    WAIT 0.1.
    LOCAL errorsig TO ABS(SteeringManager:ANGLEERROR) + ABS(SteeringManager:ROLLERROR).
    PRINT "Deviation: "+ROUND(errorsig,3).

    UNTIL errorsig < 0.1 {
        WAIT 0.1.
        SET errorsig TO errorsig*k + (ABS(SteeringManager:ANGLEERROR) + ABS(SteeringManager:ROLLERROR))*(1-k).
        PRINT "Deviation: "+ROUND(errorsig,3)+"      " AT(0,2).
        IF TERMINAL:INPUT:HASCHAR {
            IF TERMINAL:INPUT:GETCHAR() = TERMINAL:INPUT:DELETERIGHT {
                SET errorsig TO 0.
                PRINT "Aborted ..".
            }
        }
    }
    SAS ON.
}