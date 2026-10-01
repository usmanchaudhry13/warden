--  The policy: what this station allows.
--
--  Two different questions are asked of every request:
--
--     "Is it a proper Modbus message?"        Warden.Modbus, Warden.Gate
--     "Is this request allowed HERE?"         this package
--
--  A perfectly formed request can still be one nobody should send:
--  changing a safety setpoint, stopping the controller. Modbus itself
--  has no notion of permission. This package is where it gets one.

with Warden.Modbus;

package Warden.Policy with
  SPARK_Mode
is

   function Permits (Request : Modbus.Fields) return Boolean with
     Global => null;
   --  OPEN: the seed permits everything. docs/PLANT.md says what the
   --  station's registers are and which ones matter. What the rules are,
   --  and how they are written down (code? a table? a file?), is yours
   --  to decide. See docs/TRAIL.md, stop 5.

end Warden.Policy;
