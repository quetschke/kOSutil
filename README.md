# kOSutil
Repository with files and utilities for the [kOS mod](https://github.com/KSP-KOS/KOS) for Kerbal Space Program.

## Contents
The following topics are currently addressed:

### Library to provide extended staging information
The user interface of KSP provides information about Delta V, ISP, Thrust, TWR, Start/End Mass and
Burn Time, but kOS **only** makes the
[Delta V information per stage](https://ksp-kos.github.io/KOS/structures/vessels/deltav.html) available.
The ``sinfo.ks`` library recalculates those and other values and provides access to the values via a
list/lexicon structure. The values match those provided through Kerbal Engineer Redux, or MechJeb.

The library supports the use of **fuel ducts** in the vessel when calculating the staging information.

#### Files
- ``sinfo.ks``        Main library file providing the ``sinfo()`` function.
- ``sitest.ks``       A test script to demonstrate the ``sinfo()`` usage.
- ``sinfo_no_fd.ks``  A legacy version that does **not** support _fuel ducts_.

#### Documentation
[The sinfo() documentation can be found here](sinfo.md).

### Multi-stage maneuver execution script
The ``xm2.ks`` script uses the ``sinfo.ks`` library to calculate the cummulative burn time across multiple
stages to time the beginning of the burn for the maneuver. This is something that the user interface from
KSP provides, but that otherwise is not available through kOS.
The script times the ignition so that one half of the Delta V is applied before the maneuver time (``node:ETA``) and
the other half after.

### Library of frequently used functions
The ``libcommon.ks`` library contains functions that are used by the scripts and libraries above. 
The following function is provided:
```
nuform(nmber,lead,precision)  A function to format a string from a number
                              with leading characters and trailing digits.
```
## Use
All code is considered "as is" and might fail anytime. Protect your Kerbals!

## Licensing
Permission is granted to change, share, and use the content of this repository under the terms of the [MIT license](LICENSE).

