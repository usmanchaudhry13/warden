with Warden.Policy;

package body Warden.Gate with
  SPARK_Mode
is
   use type Byte;
   use type U16;

   -------------
   -- Inspect --
   -------------

   procedure Inspect
     (Input   : Byte_Array;
      Result  : out Verdict;
      Request : out Approved)
   is
      Fields : Modbus.Fields;
   begin
      Request := (Valid => False, Length => 0, Data => (others => 0));

      --  1. Can this be a Modbus/TCP message at all?
      if Input'Length < Modbus.Min_Message then
         Result := Too_Short;
         return;
      end if;

      if Input'Length > Modbus.Max_Message then
         Result := Too_Long;
         return;
      end if;

      Fields := Modbus.Decode (Input);

      if Fields.Protocol /= 0 then
         Result := Bad_Protocol;
         return;
      end if;

      if Fields.Function_Code = Modbus.Read_Holding_Registers
         or else Fields.Function_Code = Modbus.Read_Input_Registers
      then
         if Input'Length /= 12 then
            Result := Denied;
            return;
         end if;
      end if;

      if Fields.Function_Code = Modbus.Read_Holding_Registers
       or else Fields.Function_Code = Modbus.Read_Input_Registers
      then
         if Natural (Input (Input'First + 10)) * 256
         + Natural (Input (Input'First + 11)) not in 1 .. 125
         then
            Result := Denied;
            return;
         end if;
      end if;

      --  OPEN: the seed stops checking the message here. It assumes that
      --  one read from the network is exactly one request, and it never
      --  looks at the length field or past the function code. Both are
      --  wrong, and the gauntlet has an attack for each.

      --  2. Is it allowed here?

      if Fields.Function_Code = Modbus.Write_Single_Register then
         if Input'Length /= 12 then
            Result := Denied;
            return;
         end if;

         if Natural (Input (Input'First + 8)) * 256
            + Natural (Input (Input'First + 9)) /= 0
         then
            Result := Denied;
            return;
         end if;
      end if;

      if Fields.Function_Code = Modbus.Write_Multiple_Registers then
         if Input'Length /= 15 then
            Result := Denied;
            return;
         end if;

         if Natural (Input (Input'First + 8)) * 256
            + Natural (Input (Input'First + 9)) /= 0
            or else Natural (Input (Input'First + 10)) * 256
            + Natural (Input (Input'First + 11)) /= 1
            or else Input (Input'First + 12) /= 2
         then
            Result := Denied;
            return;
         end if;
      end if;

      if Fields.Function_Code = Modbus.Write_Single_Coil then
         if Input'Length /= 12 then
            Result := Denied;
            return;
         end if;

         if Natural (Input (Input'First + 8)) * 256
            + Natural (Input (Input'First + 9)) not in 0 .. 1
         then
            Result := Denied;
            return;
         end if;
         if Input (Input'First + 11) /= 0 then
            Result := Denied;
            return;
         end if;

         if Input (Input'First + 10) /= 0 then
            if Input (Input'First + 10) /= 16#FF# then
               Result := Denied;
               return;
            end if;
         end if;
      end if;

      if not Policy.Permits (Fields) then
         Result := Denied;
         return;
      end if;

      --  3. Build what will be sent.
      --
      --  OPEN: the seed copies the client's bytes as they came. A gate
      --  that understood the request could write it again from the
      --  fields it checked, so that nothing it did not check can ride
      --  along. See docs/TRAIL.md, stop 4.
      Request.Data (0 .. Input'Length - 1) := Input;
      Request.Length := Input'Length;
      Request.Valid := True;
      Result := Accepted;
   end Inspect;

end Warden.Gate;
