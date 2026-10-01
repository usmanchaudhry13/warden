package body Warden.Policy with
  SPARK_Mode
is

   -------------
   -- Permits --
   -------------

   function Permits (Request : Modbus.Fields) return Boolean is
      pragma Unreferenced (Request);
   begin
      return True;
   end Permits;

end Warden.Policy;
