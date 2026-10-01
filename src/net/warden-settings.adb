with Ada.Command_Line;

package body Warden.Settings is

   --  The value that follows Flag on the command line, or Default.
   function Value_Of (Flag : String; Default : Port) return Port is
      use Ada.Command_Line;
   begin
      for I in 1 .. Argument_Count - 1 loop
         if Argument (I) = Flag then
            return Port'Value (Argument (I + 1));
         end if;
      end loop;
      return Default;
   exception
      when Constraint_Error =>
         return Default;
   end Value_Of;

   function Listen_Port return Port is (Value_Of ("--listen", 5021));

   function Controller_Port return Port is (Value_Of ("--controller", 5020));

end Warden.Settings;
