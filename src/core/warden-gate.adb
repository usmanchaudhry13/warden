with Warden.Policy;

package body Warden.Gate with
  SPARK_Mode
is

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
      -- Danniell Note: Put_U16 is a helper to encode any 16 bit big-endian 
      -- integer into a Byte_Array at a specified position. Used for reconstruction
      procedure Put_U16
        (Data     : in out Byte_Array;
        Position  : Natural;
        Value     : U16)
      is
      begin
      -- Grabs first byte of a U16 and shifts it to the right by 8 bits. 'Byte' casting kills 
      -- the padding bits, leaving only the first 8 bits of the U16 value
         Data (Position) :=
           Byte (Interfaces.Shift_Right (Value, 8));
      
      -- Performs a bitwise AND with a U16 and 16#00FF# to leave just the last 8 bits of the U16 value. 
      -- 'Byte' casting kills the padding bits, leaving only the last 8 bits of the U16 value
         Data (Position + 1) :=                        
           Byte (Value and 16#00FF#);
      end Put_U16;
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

      Fields := Modbus.Decode (Input); -- This call should provide all fields of Modbus message

      if Fields.Protocol /= 0 then
         Result := Bad_Protocol;
         return;
      end if;

      if not Modbus.Validate (Fields) then -- Placeholder call on Validate to check all complete fields of Modbus message, expecting a boolean
         Result := Invalid_Message; -- Danniell Note: Added Invalid_Message to Verdict type to handle this case
         return;
      end if;

      --  OPEN: the seed stops checking the message here. It assumes that
      --  one read from the network is exactly one request, and it never
      --  looks at the length field or past the function code. Both are
      --  wrong, and the gauntlet has an attack for each.
      --  Danniell Note: This is resolved above as .Validate expects to check all fields of Modbus message

      --  2. Is it allowed here?
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

      -- Danniell Note: Start encoding the MBAP fields + Function code field 
      -- of the decoded message as it's implicitly validated to reach 
      -- this point. MBAP Fields have consistent structure across all 
      -- Modbus/TCP messages, so this is a safe assumption to make.
      Put_U16 (Request.Data, 0, Fields.Transaction);  -- Places Transaction into bytes 0 and 1 of Request.Data
      Put_U16 (Request.Data, 2, U16(0));              -- Places 16#0000# into bytes 2 and 3 of Request.Data
      Request.Data (6) := Fields.Unit;                -- Places Unit into byte 6 of Request.Data
      Request.Data (7) := Fields.Function_Code;       -- Places Function_Code into byte 7 of Request.Data
      
      -- With MBAP fields + Function_Code encoded, case on Fields.Function_Code 
      -- is used to determine the structure of remaining PDU fields
      case Fields.Function_Code is
         when 1 | 2 | 3 | 4 => -- Read Coils, Read Discrete Inputs, Read Holding Registers, Read Input Registers
            -- Remaining PDU fields are Address (2 bytes) and Quantity (2 bytes)
            Put_U16 (Request.Data, 4, U16(6));           -- Places 16#0006# into bytes 4 and 5 of Request.Data, length is always 6 for these function codes
            Put_U16 (Request.Data, 8, Fields.Address);   -- Places Address into bytes 8 and 9 of Request.Data
            Put_U16 (Request.Data, 10, Fields.Quantity); -- Places Quantity into bytes 10 and 11 of Request.Data
            Request.Length := 12;                        -- Total length of Request.Data for these function codes is 12 bytes

            
         when 5 | 6 => -- Write Single Coil, Write Single Register
            -- Remaining PDU fields are Address (2 bytes) and Value (2 bytes)
            Put_U16 (Request.Data, 4, U16(6));           -- Places 16#0006# into bytes 4 and 5 of Request.Data, length is always 6 for these function codes
            Put_U16 (Request.Data, 8, Fields.Address);   -- Places Address into bytes 8 and 9 of Request.Data
            Put_U16 (Request.Data, 10, Fields.Value);    -- Places Value into bytes 10 and 11 of Request.Data
            Request.Length := 12;                        -- Total length of Request.Data for these function codes is 12 bytes

         when 16 => -- Write Multiple Registers
            -- Remaining PDU fields are Address (2 bytes), Quantity (2 bytes), Byte Count (1 byte), and Value (Quantity x 2 bytes)
            Put_U16 (Request.Data, 4, (U16 (7) + (U16 (2) * Fields.Quantity))); -- Places length into bytes 4 and 5 of Request.Data, length is 7 + Byte Count for this function code
            Put_U16 (Request.Data, 8, Fields.Address);               -- Places Address into bytes 8 and 9 of Request.Data
            Put_U16 (Request.Data, 10, Fields.Quantity);             -- Places Quantity into bytes 10 and 11 of Request.Data
            Request.Data (12) := Byte (U16 (2) * Fields.Quantity);   -- Calculates and places Byte_Count into byte 12 of Request.Data
            for i in 0 .. Fields.Quantity - 1 loop
               Put_U16 (Request.Data, 13 + i * 2, Fields.Values (i)); -- Places each Value into Request.Data starting at byte 13
            -- NEED TO CHECK FIELDS.VALUES TO SEE HOW STRUCTURE IS DEFINED, THIS ASSUMES IT'S ARRAY OF U16s
            end loop;
            Request.Length := 13 + Natural (Request.Data (12));

      end case;

      -- Request.Data (0 .. Input'Length - 1) := Input;
      -- Request.Length := Request.Data'Length;
      Request.Valid := True;
      Result := Accepted;
   end Inspect;

end Warden.Gate;
