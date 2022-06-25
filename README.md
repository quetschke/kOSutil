# kOSutil
Repository with files and utilities for the [kOS mod](https://github.com/KSP-KOS/KOS) for Kerbal Space Program.

***

### Table of Contents
Library to provide extended staging information

Multi-stage maneuver execution script

Automated launch scripts

Script to very precisely set the Orbital Period of a craft

Other supporting scrips

***

### Library to provide extended staging information
- ``sinfo.ks``        Main library file providing the ``sinfo()`` function.
- ``sitest.ks``       A test script to demonstrate the ``sinfo()`` usage.
- ``sinfo_no_fd.ks``  A legacy version that does **not** support _fuel ducts_.

The user interface of KSP provides information about Delta V, ISP, Thrust, TWR, Start/End Mass and
Burn Time, but kOS **only** makes the
[Delta V information per stage](https://ksp-kos.github.io/KOS/structures/vessels/deltav.html) available.
The ``sinfo.ks`` library recalculates those and other values and provides access to the values via a
list/lexicon structure. The values match those provided through Kerbal Engineer Redux, or MechJeb.

The library supports the use of **fuel ducts** in the vessel when calculating the staging information.

#### Documentation
[The sinfo() documentation can be found here](sinfo.md).

### Multi-stage maneuver execution script
- ``xm2.ks``          Script to perform multi-stage maneuver.

The ``xm2.ks`` script uses the ``sinfo.ks`` library to calculate the cummulative burn time across multiple
stages to time the beginning of the burn for the maneuver. This is something that the user interface from
KSP provides, but that otherwise is not available through kOS.
The script times the ignition so that one half of the Delta V is applied before the maneuver time (``node:ETA``) and
the other half after.

The ``xm2.ks`` script uses the ``sinfo.ks`` library to calculate the cummulative burn time across multiple

### Automated launch scripts
- ``Launch.ks``       Script to launch now.<br>
     Syntax: ``run Launch(targetAltkm=80,targetIncl=0).``
- ``LauIn.ks``        Script to launch in requested number of minutes.<br>
     Syntax: ``run LauIn(targetAltkm=80,targetIncl=0,InMinutes=5).``
- ``LauLAN.ks``       Script to launch into requested LAN. Default is Minmus.<br>
     Syntax: ``run LauLAN(targetAltkm=80,targetIncl=0,lauLAN=78).``
- ``LauTarget.ks``    Script to launch into orbit with inclination and LAN from selected target.<br>
     Syntax: ``run LauLAN(targetAltkm=80).``
- ``LauEject.ks``     Script to launch into target orbit with ejection angle provided by Transfer
     Window Planner. See Mike Aben's Eve/Moho Flyby Build https://youtu.be/pvl8zILT5Wc?t=1498 for an example.<br>
     Syntax: ``run LauEject(targetAltkm=80,targetIncl=5,ejectAng=5).``


### Script to very precisely set the Orbital Period of a craft
- ``SetPeriod.ks``    Script to adjust orbital period.

The ``SetPeriod.ks`` script takes one parameter that sets the target orbital period of a vessel in seconds. The burn is executed immediately and will result in an orbital period that is less than one microsecond (1 us) deviating from the target period.

### Other supporting scrips
These script are called by some of the scripts listed above or can be used independently.
- ``Align.ks``        Script to align vessel. Orientations: 'n' - normal, 'd' - dorsal, 'w' - wing (dorsal+90deg)<br>
    Syntax: ``run Align(orientation=n).``
- ``Ascent.ks``       Helper script for launch scripts to launch into target orbit.
- ``CircAtAP.ks``     Script that creates a maneuver node to circularize at next apoapsis.<br>
    Syntax: ``run CircAtAP.ks.``
- ``CircAtPE.ks``     Script that creates a maneuver node to circularize at next periapsis.<br>
    Syntax: ``run CircAtPE.ks.``
- ``libcommon.ks``    A library providing the following function:<br>
    Syntax: ``nuform(nmber,lead,precision)``  A function to format a string from a number with leading
            characters and trailing digits.

***

## Use
All code is considered "as is" and might fail anytime. Protect your Kerbals!

## Licensing
Permission is granted to change, share, and use the content of this repository under the terms of the [MIT license](LICENSE).

