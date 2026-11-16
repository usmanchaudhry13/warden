with Interfaces;

package body Warden.Modbus with
  SPARK_Mode
is
   use type Byte;
   use type U16;

   function Get_U16
     (Raw : Byte_Array; Offset : Natural) return U16 is
     (Interfaces.Shift_Left (U16 (Raw (Offset)), 8)
      or U16 (Raw (Offset + 1)))
   with
      Pre => Raw'First = 0 and then
             Offset < Raw'Length and then
             Offset + 1 < Raw'Length;

   procedure Put_U16
     (Raw : in out Byte_Array; Offset : Natural; Number : U16)
   with
      Pre => Raw'First = 0 and then
             Offset < Raw'Length and then
             Offset + 1 < Raw'Length
   is
   begin
      Raw (Offset) := Byte (Interfaces.Shift_Right (Number, 8));
      Raw (Offset + 1) := Byte (Number and U16 (16#00FF#));
   end Put_U16;

   --  Original decoding function, retained for old Warden.Gate callers.
   function Decode (Raw : Byte_Array) return Fields is
     (Transaction   =>
         Interfaces.Shift_Left (U16 (Raw (Raw'First)), 8)
         or U16 (Raw (Raw'First + 1)),
      Protocol      =>
         Interfaces.Shift_Left (U16 (Raw (Raw'First + 2)), 8)
         or U16 (Raw (Raw'First + 3)),
      Length        =>
         Interfaces.Shift_Left (U16 (Raw (Raw'First + 4)), 8)
         or U16 (Raw (Raw'First + 5)),
      Unit          => Raw (Raw'First + 6),
      Function_Code => Raw (Raw'First + 7));

   procedure Parse
     (Raw     : Byte_Array;
      Success : out Boolean;
      Request : out Validated_Request)
   is
      Transaction_Id : U16 := 0;
      Unit_Id        : Byte := 0;
      Function_Id    : Byte := 0;
      Start_Address  : U16 := 0;
      Count          : U16 := 0;
      Single_Value   : U16 := 0;
      Words          : Register_Values := (others => 0);
   begin
      --  Fail closed; no partial/previous request can remain approved.
      Request := (Valid              => False,
                  Transaction_Field  => 0,
                  Unit_Field         => 0,
                  Function_Field     => 0,
                  Address_Field      => 0,
                  Quantity_Field     => 0,
                  Single_Value_Field => 0,
                  Values_Field       => (others => 0));
      Success := False;

      if Raw'Length < Min_Message or else Raw'Length > Max_Message then
         return;
      end if;

      --  A Modbus/TCP MBAP header has protocol ID 0 and a length equal to
      --  the number of bytes after the two-byte Length field.
      if Get_U16 (Raw, 2) /= 0 then
         return;
      end if;

      if Natural (Get_U16 (Raw, 4)) /= Raw'Length - 6 then
         return;
      end if;

      Transaction_Id := Get_U16 (Raw, 0);
      Unit_Id := Raw (6);
      Function_Id := Raw (7);

      case Function_Id is
         when Read_Coils | Read_Discrete_Inputs |
              Read_Holding_Registers | Read_Input_Registers =>
            if Raw'Length /= 12 then
               return;
            end if;

            Start_Address := Get_U16 (Raw, 8);
            Count := Get_U16 (Raw, 10);

            if Function_Id = Read_Coils or else
               Function_Id = Read_Discrete_Inputs
            then
               if Count not in 1 .. 2000 then
                  return;
               end if;
            else
               if Count not in 1 .. 125 then
                  return;
               end if;
            end if;

         when Write_Single_Coil | Write_Single_Register =>
            if Raw'Length /= 12 then
               return;
            end if;

            Start_Address := Get_U16 (Raw, 8);
            Count := 1;
            Single_Value := Get_U16 (Raw, 10);

            if Function_Id = Write_Single_Coil and then
              (Single_Value /= 0 and then Single_Value /= 16#FF00#)
            then
               return;
            end if;

         when Write_Multiple_Registers =>
            if Raw'Length < 15 then
               return;
            end if;

            Start_Address := Get_U16 (Raw, 8);
            Count := Get_U16 (Raw, 10);

            if Count not in 1 .. 123 then
               return;
            end if;

            if Natural (Raw (12)) /= 2 * Natural (Count) then
               return;
            end if;

            if Raw'Length /= 13 + 2 * Natural (Count) then
               return;
            end if;

            for I in 0 .. Natural (Count) - 1 loop
               Words (I) := Get_U16 (Raw, 13 + 2 * I);
            end loop;

         when others =>
            --  Includes custom controller-stop 0x5A: never recognized.
            return;
      end case;

      --  Address 0..65535; the final addressed item must still fit.
      --  Use Natural arithmetic so this check cannot wrap around at U16.
      if Natural (Start_Address) + Natural (Count) > 65_536 then
         return;
      end if;

      Request := (Valid              => True,
                  Transaction_Field  => Transaction_Id,
                  Unit_Field         => Unit_Id,
                  Function_Field     => Function_Id,
                  Address_Field      => Start_Address,
                  Quantity_Field     => Count,
                  Single_Value_Field => Single_Value,
                  Values_Field       => Words);
      Success := True;
   end Parse;

   function Transaction (R : Validated_Request) return U16 is
     (R.Transaction_Field);

   function Unit (R : Validated_Request) return Byte is
     (R.Unit_Field);

   function Function_Code (R : Validated_Request) return Byte is
     (R.Function_Field);

   function Address (R : Validated_Request) return U16 is
     (R.Address_Field);

   function Quantity (R : Validated_Request) return U16 is
     (R.Quantity_Field);

   function Value (R : Validated_Request) return U16 is
     (R.Single_Value_Field);

   function Register_Value
     (R : Validated_Request; Index : Natural) return U16 is
     (R.Values_Field (Index));

   function Encoded_Length (R : Validated_Request) return Natural is
     (if R.Function_Field = Write_Multiple_Registers
      then 13 + 2 * Natural (R.Quantity_Field)
      else 12);

   function Encode (R : Validated_Request) return Byte_Array is
      Output : Byte_Array (0 .. Encoded_Length (R) - 1) := (others => 0);
   begin
      --  Header and PDU fields are reconstructed, not copied from input.
      Put_U16 (Output, 0, R.Transaction_Field);
      --  Protocol ID (2..3) remains zero by initialization.
      Put_U16 (Output, 4, U16 (Output'Length - 6));
      Output (6) := R.Unit_Field;
      Output (7) := R.Function_Field;
      Put_U16 (Output, 8, R.Address_Field);

      case R.Function_Field is
         when Read_Coils | Read_Discrete_Inputs |
              Read_Holding_Registers | Read_Input_Registers |
              Write_Multiple_Registers =>
            Put_U16 (Output, 10, R.Quantity_Field);

         when Write_Single_Coil | Write_Single_Register =>
            Put_U16 (Output, 10, R.Single_Value_Field);

         when others =>
            null;  --  Unreachable for Is_Valid (R)
      end case;

      if R.Function_Field = Write_Multiple_Registers then
         Output (12) := Byte (2 * Natural (R.Quantity_Field));
         for I in 0 .. Natural (R.Quantity_Field) - 1 loop
            Put_U16 (Output, 13 + 2 * I, R.Values_Field (I));
         end loop;
      end if;

      return Output;
   end Encode;
end Warden.Modbus;
