package body Warden.Policy with
  SPARK_Mode
is

   -------------
   -- Permits --
   -------------

   function Permits (Request : Modbus.Fields) return Boolean is
   begin
      case Request.Function_Code is
         when Modbus.Read_Coils
            | Modbus.Read_Discrete_Inputs
            | Modbus.Read_Holding_Registers
            | Modbus.Read_Input_Registers
            | Modbus.Write_Single_Coil
            | Modbus.Write_Single_Register
            | Modbus.Write_Multiple_Registers =>
            return True;

         when others =>
            return False;
      end case;
   end Permits;

end Warden.Policy;