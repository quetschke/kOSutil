# Documentation for extended staging information library (sinfo())

The user interface of KSP provides information about Delta V, ISP, Thrust, TWR, Start/End Mass and
Burn Time, but kOS **only** makes the
[Delta V information per stage](https://ksp-kos.github.io/KOS/structures/vessels/deltav.html) available.
The ``sinfo.ks`` library recalculates those and other values and provides access to the values via a
list/lexicon structure. The values match those provided through Kerbal Engineer Redux, or MechJeb.

The library supports the use of fuel ducts in the vessel when calculating the staging information.

#### Files
- ``sinfo.ks``        Main library file providing the ``sinfo()`` function.
- ``sitest.ks``       A test script to demonstrate the ``sinfo()`` usage.
- ``sinfo_no_fd.ks``  A legacy version that does **not** support _fuel ducts_.

#### sinfo function
Calculates and returns extended staging information.

##### Arguments:
```
1) atmo:  Optional - Sets the atmostpheric pressure to be used.
          Allowed values:
            any non scalar (default) Any non number value makes the function to use the pressure
                           at the current location of the vessel.
            0 to 100       A numeric value of zero to 100 sets the atmostpheric pressure to this
                           value in atmospheres.
```
##### Return value:
```
On failure: 0 (integer value)
On success: A list of lexicons with one lexicon entry per stage with the following keys.
            (format returnvar[stage]:key):
  SMass   .. startmass
  EMass   .. endmass.
  DMass   .. stagedmass.
  BMass   .. fuel burned
  sTWR    .. start TWR
  maxTWR  .. max TWR
  sSLT    .. start SLT (Sea Level Thrust)
  maxSLT  .. max SLT
  FtV     .. thrust in vacuum
  FtA     .. thrust at atmospheric pressure
  KSPispV .. ISPg0 KSP - vacuum
  KERispV .. ISPg0 Kerbal Engineer Redux - vacuum
  KSPispA .. ISPg0 KSP - at atmospheric pressure
  KERispA .. ISPg0 Kerbal Engineer Redux - at atmospheric pressure
  VdV     .. Vacuum delta V
  AdV     .. Atmospheric delta V (see atmo parameter)
  dur     .. burn duration
  ATMO    .. Atmospheric pressure used for thrust calculation (same value in all stages)
```

#### Requirements and Usage
The function simulates the fuel consumption and thrust, more on that below, to calculate the Delta V (this implies knowing ISP and mass) available for each of the stages. Some assumptions are made as laid out below. Violation of these requrements will likely lead to incorrect staging information or an error message.
* **Fuel Ducts** need some additional preparations and precautions:
  * Use [kOS tags](https://ksp-kos.github.io/KOS/general/nametag.html) to mark the target of the duct. Assigning the same _tag_ to the fuel duct and the target it attaches to will tell the function where it connects to. See also Figure 1 (left) below. This is needed because kOS does [not provide the target information of the part](https://github.com/KSP-KOS/KOS/issues/1974) that the duct connects to.
  * If no suitable tags are found, the function assumes the other side of the decoupler that drops the part or group of parts where the fuel duct is attached to as the target of the fuel duct. This works in simple cases, but the asparagus staging example from Figure 1 needs tags to assist the sinfo library.
* **Only one** fuel duct **leading out** of a _fuel zone_ (group of tanks and engines) into another target group is supported. No such limit is imposed on **incoming** fuel ducts into a [_fuel zone_](#Engine-groups-or-fuel-zones). This is a limitation of the underlying framework. 
* The function assumes that the group that the duct leads out (_source_) is **decoupled earlier** than the group the duct targets to (_target_). This assures that the **_source_ is drained completely before drawing fuel from the _target_**. This is KSP's default behavior, unless the flow priority of the tanks is changed - be careful!
* **Flow Priority** of the tanks is not considered when simulating the fuel usage, but might lead to unexpected results when altered.

#### Caveats
* Air breathing engines are not considered and might break the function.
* Solid Rocket Boosters within the same [_fuel zone_](#Engine-groups-or-fuel-zones) need to be of the same type with the same thrust, consumption rate and fuel mass.
* The library is not tested with non-stock parts.

#### Figures
<img src="img/sinfo_fig2a.jpg" width="49%"></img> <img src="img/sinfo_fig1a.jpg" width="49%"></img>
**Figure 1:** (left) Vessel in the VAB with KER readout and showing kOS tags. (right) Vessel showing staging information after executing sitest.ks and also showing MechJeb vessel information for comparison.

### Example Usage
Copy ``sinfo.ks`` and ``sitest.ks`` on your kOS volume and ``run sitest.`` in your kOS terminal window. You will see extended staging information like shown in the kOS terminal window in Figure 1 (right).

### Under the hood
This section will describe the method to calculate the extended staging information that is used by this function.  The information about Delta V, ISP, Thrust, TWR, Start/End Mass and Burn Time is provided by the KSP user interface and extended information can be obtained by using [Kerbal Engineer Redux](https://forum.kerbalspaceprogram.com/index.php?/topic/17833-130-kerbal-engineer-redux-1130-2017-05-28/) or [MechJeb](https://forum.kerbalspaceprogram.com/index.php?/topic/154834-112x-anatid-robotics-mumech-mechjeb-autopilot-2121-8th-august-2021/&ct=1628797784). Unfortunately, neither of those sources is available through kOS.

The calculation of Delta V requires the knowledge of fuel consumption and thrust (this implies ISP and mass). The function calculates this and related information for every stage of the vessel. The computing power of kOS prohibits a brute force approach that would simulate the fuel usage obeying flow priorities with [physics ticks](https://ksp-kos.github.io/KOS/general/cpu_hardware.html?highlight=physics%20ticks#update-ticks-and-physics-ticks) accuracy. MechJeb, for example, uses this approach.

The limitations of kOS's computation speed led to the approach as laid out below to be used for the sinfo function. 

#### Engine groups or fuel zones
The function looks at every part of the vessel and groups them together when crossfeed is enabled between touching parts. That means all parts in one of those groups have access to all the fuel in this group. The exception from this are SRBs, they do not _share_ their own fuel, but allow for crossfeed and connect other parts in the same group.

Defining engine groups allows to track fuel, fuel consumption and thrust per engine group.

#### Staging
For stages with decouplers, KSP (and this function) assumes that it will immediately stage after all active engines connected to this decoupler are out of all available fuel.

#### Tracking changes when a stage is activated - burning
The Delta V calculation is straight forward when the thrust and rate of fuel consumption stay constant for the full duration of the burn until all fuel in the stage has been used up. When multiple engine groups with different burn durations, different fuel consumption rates and different engine types with different fuels (rocket engines, nuclear engines, ion drives and solid rocket boosters) are present the total burn duration of the stage needs to be split up in smaller intervals.

To accomodate this, the burn is split into the longest possible intervals where the thrust and rate of fuel consumption stay constant, these intervals are called substages below.

This is achieved looking for the minmum burn time of any of the engine groups for all participating engine types. For this interval the consuption rate and thrust of all active engines in all engine groups is calculated and then the fuel in the engine group is reduced accordingly.

After this fuel consumption the next minimum burn time is found and the fuel is consumed accordingly again. This is repeated until no usable fuel in any of the engine groups that are about to be staged is left. Then staging can occur and the process starts again for the next stage.

#### Fuel Ducts
The description above allows for the calculation of Delta V for various tank and engine configarations including the separation of engine groups that have used up their fuel. But fuel ducts require some additional considerations. Fuel duct usage is based on the method that when multiple engine groups are linked by a fuel duct the fuel is used up in the upstream engine group first, but the fuel consumption rates and thrusts of all downstream engine groups are used to burn that fuel. If multiple engine grouups connect to one downstream group the consumption and thrust is divided up evenly to the upstream engine groups. The same principle applies when there are further downstream engine groups connected with fuel ducts. 

This fits into the substage model as the downstream consumption and thrust is considered part of the topmost upstream engine group. The downstream groups are not considered individually until the upstream group runs empty and is staged/decoupled away.

This simplistic description gets complicated by the fact rocket engines need two types of fuel to run and that those fuels can be provided by two different engine groups feeding into a downstream engine group. In this case the upstream groups don't consume any fuel and do not produce thrust, but only the first downstream group that has both fuel types actually starts to consume fuel and thrust. Please refer to the code of ``sinfo.ks`` for further information.

