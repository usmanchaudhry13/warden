--  Standalone tests of the Warden.Modbus parser/encoder.
--  Tests structure only; station allowlist belongs to Warden.Policy.
with Ada.Text_IO;
with Interfaces;
with Warden;
with Warden.Modbus;

procedure Warden_Modbus_Test is
   use Ada.Text_IO;
   use Warden;
   use Warden.Modbus;
   use type Byte;
   use type U16;
   use type Byte_Array;

   Passed : Natural := 0;

   procedure Require (Condition : Boolean; Reason : String) is
   begin
      if not Condition then
         raise Program_Error with Reason;
      end if;
   end Require;

   procedure Put_U16
     (A : in out Byte_Array; Offset : Natural; X : U16)
   is
   begin
      A (Offset) := Byte (Interfaces.Shift_Right (X, 8));
      A (Offset + 1) := Byte (X and U16 (16#00FF#));
   end Put_U16;

   function Read_Frame
     (F : Byte; Addr : U16; Q : U16) return Byte_Array
   is
      A : Byte_Array (0 .. 11) := (others => 0);
   begin
      Put_U16 (A, 0, 1);
      Put_U16 (A, 4, 6);
      A (6) := 1;
      A (7) := F;
      Put_U16 (A, 8, Addr);
      Put_U16 (A, 10, Q);
      return A;
   end Read_Frame;

   function Single_Frame
     (F : Byte; Addr : U16; V : U16) return Byte_Array
   is
      A : Byte_Array (0 .. 11) := Read_Frame (F, Addr, V);
   begin
      return A;
   end Single_Frame;

   function Multi_Frame
     (Addr : U16; Q : Positive) return Byte_Array
   is
      A : Byte_Array (0 .. 13 + 2 * Q - 1) := (others => 0);
   begin
      Put_U16 (A, 0, 1);
      Put_U16 (A, 4, U16 (A'Length - 6));
      A (6) := 1;
      A (7) := Write_Multiple_Registers;
      Put_U16 (A, 8, Addr);
      Put_U16 (A, 10, U16 (Q));
      A (12) := Byte (2 * Q);
      for I in 0 .. Q - 1 loop
         Put_U16 (A, 13 + 2 * I, U16 (100 + I));
      end loop;
      return A;
   end Multi_Frame;

   procedure Check_Valid (Label : String; Raw : Byte_Array) is
      Good : Boolean;
      R    : Validated_Request;
   begin
      Parse (Raw, Good, R);
      Require (Good and then Is_Valid (R), Label & ": rejected valid frame");
      Require (Transaction (R) = 1, Label & ": wrong transaction ID");
      Require (Unit (R) = 1, Label & ": wrong unit ID");
      Require (Function_Code (R) = Raw (7), Label & ": wrong function");
      declare
         Encoded : constant Byte_Array := Encode (R);
      begin
         Require (Encoded = Raw, Label & ": encode changed canonical frame");
         Require (Encoded'Length = Encoded_Length (R),
                  Label & ": wrong canonical size");
      end;
      Passed := Passed + 1;
      Put_Line ("PASS " & Label);
   end Check_Valid;

   procedure Check_Invalid (Label : String; Raw : Byte_Array) is
      Good : Boolean;
      R    : Validated_Request;
   begin
      Parse (Raw, Good, R);
      Require (not Good and then not Is_Valid (R),
               Label & ": accepted invalid frame");
      Passed := Passed + 1;
      Put_Line ("PASS " & Label);
   end Check_Invalid;

begin
   --  All seven supported functions and boundary legal quantities.
   Check_Valid ("read coils", Read_Frame (Read_Coils, 0, 2));
   Check_Valid ("read discrete inputs", Read_Frame (Read_Discrete_Inputs, 0, 2));
   Check_Valid ("read holding registers", Read_Frame (Read_Holding_Registers, 0, 16));
   Check_Valid ("read input registers", Read_Frame (Read_Input_Registers, 0, 3));
   Check_Valid ("max coils quantity", Read_Frame (Read_Coils, 0, 2_000));
   Check_Valid ("max registers quantity", Read_Frame (Read_Holding_Registers, 0, 125));
   Check_Valid ("last legal Modbus address", Read_Frame (Read_Coils, 65_535, 1));
   Check_Valid ("coil ON", Single_Frame (Write_Single_Coil, 0, 16#FF00#));
   Check_Valid ("coil OFF", Single_Frame (Write_Single_Coil, 1, 0));
   Check_Valid ("single register 10 structurally valid", Single_Frame (Write_Single_Register, 10, 900));
   Check_Valid ("one-register block write", Multi_Frame (0, 1));
   Check_Valid ("largest legal block write", Multi_Frame (0, 123));
   Check_Valid ("protected-range block structurally valid", Multi_Frame (0, 11));

   declare
      Good : Boolean;
      R    : Validated_Request;
      A    : constant Byte_Array := Multi_Frame (0, 2);
   begin
      Parse (A, Good, R);
      Require (Good, "two-register block must parse");
      Require (Address (R) = 0 and then Quantity (R) = 2,
               "block address/quantity fields");
      Require (Register_Value (R, 0) = 100 and then
               Register_Value (R, 1) = 101,
               "block values in big-endian order");
      Passed := Passed + 1;
      Put_Line ("PASS typed multi-register payload");
   end;

   declare
      A : Byte_Array (0 .. 6) := (others => 0);
   begin
      Check_Invalid ("too short", A);
   end;

   declare
      A : Byte_Array (0 .. 260) := (others => 0);
   begin
      Check_Invalid ("over 260 bytes", A);
   end;

   declare
      A : Byte_Array := Read_Frame (Read_Input_Registers, 0, 1);
   begin
      A (2) := 1;
      Check_Invalid ("bad protocol ID", A);
   end;

   declare
      A : Byte_Array := Read_Frame (Read_Input_Registers, 0, 1);
   begin
      A (5) := 7;
      Check_Invalid ("MBAP length mismatch", A);
   end;

   declare
      A : Byte_Array := Read_Frame (Read_Input_Registers, 0, 1);
   begin
      A (7) := 16#5A#;
      Check_Invalid ("vendor controller-stop function", A);
   end;

   Check_Invalid ("zero read quantity", Read_Frame (Read_Coils, 0, 0));
   Check_Invalid ("coils quantity >2000", Read_Frame (Read_Coils, 0, 2_001));
   Check_Invalid ("register quantity >125", Read_Frame (Read_Holding_Registers, 0, 126));
   Check_Invalid ("address range overflow", Read_Frame (Read_Coils, 65_535, 2));
   Check_Invalid ("illegal single-coil value", Single_Frame (Write_Single_Coil, 0, 1));

   declare
      A : Byte_Array := Multi_Frame (0, 2);
   begin
      A (12) := 2; --  Should be 4 data bytes.
      Check_Invalid ("function 16 byte count mismatch", A);
   end;

   declare
      A : Byte_Array := Multi_Frame (0, 2);
   begin
      A (11) := 3; --  Claims three registers, supplied only two.
      Check_Invalid ("function 16 quantity/data mismatch", A);
   end;

   declare
      A : Byte_Array := Multi_Frame (0, 123);
   begin
      A (11) := 124; --  Bounded, otherwise well-formed frame claims too many.
      Check_Invalid ("function 16 quantity outside 1..123", A);
   end;

   declare
      A : Byte_Array := Multi_Frame (0, 1);
   begin
      A (11) := 0;
      A (12) := 0;
      Check_Invalid ("function 16 zero quantity", A);
   end;

   declare
      A : Byte_Array := Multi_Frame (65_535, 2);
   begin
      Check_Invalid ("function 16 address overflow", A);
   end;

   declare
      A : constant Byte_Array := Multi_Frame (0, 124);
   begin
      Check_Invalid ("function 16 quantity >123", A);
   end;

   declare
      A : Byte_Array (0 .. 23) := (others => 0);
      B : constant Byte_Array := Read_Frame (Read_Input_Registers, 0, 1);
   begin
      A (0 .. 11) := B;
      A (12 .. 23) := B;
      Check_Invalid ("two frames passed as one", A);
   end;

   --  Ensure parsing a bad message after a good one invalidates the result.
   declare
      Good : Boolean;
      R : Validated_Request;
   begin
      Parse (Read_Frame (Read_Input_Registers, 0, 1), Good, R);
      Require (Good, "first parse should pass");
      Parse (Read_Frame (Read_Input_Registers, 0, 0), Good, R);
      Require (not Good and then not Is_Valid (R),
               "bad parse must clear previously validated request");
      Passed := Passed + 1;
      Put_Line ("PASS failure resets request");
   end;

   Put_Line ("All" & Natural'Image (Passed) & " parser checks passed.");
end Warden_Modbus_Test;
