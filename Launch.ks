// Launch.ks - Launch script
// Copyright © 2021, 2022 V. Quetschke
// Version 0.21, 06/22/2022

DECLARE PARAMETER targetAltkm IS 80,
    targetIncl IS 0.

// Store current IPU value.
LOCAL myIPU TO CONFIG:IPU.
SET CONFIG:IPU TO 2000. // Makes the timing a little better.

LOCAL targetAlt TO targetAltkm*1000.

RUNPATH("Ascent",targetAlt,targetIncl).
RUNPATH("CircAtAP").
RUNPATH("xm2").

SET CONFIG:IPU TO myIPU. // Restores original value.