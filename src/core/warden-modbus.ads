--  WARDEN Modbus/TCP parser and canonical encoder.
--  Parse checks protocol structure, NOT pumping-station authorization.
--  The only way to obtain a valid Validated_Request is Parse.
--  Other packages consume its read-only accessors.
--
--  Existing Decode/Fields API is retained temporarily so the unmodified
--  Warden.Gate in the current repository can still compile.

package Warden.Modbus with
  Pure,
  SPARK_Mode
is
   --  Make operators on the unsigned byte/word types visible.
   use type Byte;
   use type U16;

   Header_Size : constant := 7;
   Min_Message : constant := Header_Size + 1;
   Max_Message : constant := Header_Size + 253;

   Read_Coils               : constant Byte := 1;
   Read_Discrete_Inputs     : constant Byte := 2;
   Read_Holding_Registers   : constant Byte := 3;
   Read_Input_Registers     : constant Byte := 4;
   Write_Single_Coil        : constant Byte := 5;
   Write_Single_Register    : constant Byte := 6;
   Write_Multiple_Registers : constant Byte := 16;

   --  Backward compatibility with the original gate (header-only decode).
   type Fields is record
      Transaction   : U16;
      Protocol      : U16;
      Length        : U16;
      Unit          : Byte;
      Function_Code : Byte;
   end record;

   function Decode (Raw : Byte_Array) return Fields with
      Global => null,
      Pre => Raw'Length >= Min_Message;

   --  A syntactically valid, complete request. The private representation
   --  prevents the policy or gate from manufacturing a valid request.
   type Validated_Request is private;

   function Is_Valid (R : Validated_Request) return Boolean;

   procedure Parse
     (Raw     : Byte_Array;
      Success : out Boolean;
      Request : out Validated_Request)
   with
      Global => null,
      Pre  => Raw'First = 0,
      Post => Success = Is_Valid (Request);
   --  Rejects invalid frames, lengths, functions, quantities, coil
   --  encodings, overflowing address ranges, and inconsistent write counts.
   --  Station-specific register permissions belong in Warden.Policy.

   function Transaction (R : Validated_Request) return U16 with
      Global => null,
      Pre => Is_Valid (R);

   function Unit (R : Validated_Request) return Byte with
      Global => null,
      Pre => Is_Valid (R);

   function Function_Code (R : Validated_Request) return Byte with
      Global => null,
      Pre => Is_Valid (R);

   function Address (R : Validated_Request) return U16 with
      Global => null,
      Pre => Is_Valid (R);

   function Quantity (R : Validated_Request) return U16 with
      Global => null,
      Pre => Is_Valid (R);

   --  Call only for function 5 or 6.
   function Value (R : Validated_Request) return U16 with
      Global => null,
      Pre => Is_Valid (R) and then
        (Function_Code (R) = Write_Single_Coil or else
         Function_Code (R) = Write_Single_Register);

   --  Index is zero based. Call only for function 16.
   function Register_Value
     (R : Validated_Request; Index : Natural) return U16
   with
      Global => null,
      Pre => Is_Valid (R) and then
        Function_Code (R) = Write_Multiple_Registers and then
        Index < Natural (Quantity (R));

   function Encoded_Length (R : Validated_Request) return Natural with
      Global => null,
      Pre => Is_Valid (R),
      Post => Encoded_Length'Result in 12 .. Max_Message;

   --  Construct a new, canonical Modbus/TCP message from checked fields.
   --  NOT a copy of the source buffer.
   function Encode (R : Validated_Request) return Byte_Array with
      Global => null,
      Pre  => Is_Valid (R),
      Post => Encode'Result'First = 0 and then
              Encode'Result'Length = Encoded_Length (R);

private
   type Register_Values is array (Natural range 0 .. 122) of U16;

   type Validated_Request is record
      Valid              : Boolean := False;
      Transaction_Field  : U16 := 0;
      Unit_Field         : Byte := 0;
      Function_Field     : Byte := 0;
      Address_Field      : U16 := 0;
      Quantity_Field     : U16 := 0;
      Single_Value_Field : U16 := 0;
      Values_Field       : Register_Values := (others => 0);
   end record;

   --  Encodes the key structural invariants used by callers/encoder.
   function Is_Valid (R : Validated_Request) return Boolean is
     (R.Valid and then
       (case R.Function_Field is
          when Read_Coils | Read_Discrete_Inputs =>
            R.Quantity_Field in 1 .. 2000,
          when Read_Holding_Registers | Read_Input_Registers =>
            R.Quantity_Field in 1 .. 125,
          when Write_Single_Coil =>
            R.Quantity_Field = 1 and then
            (R.Single_Value_Field = 0 or else
             R.Single_Value_Field = 16#FF00#),
          when Write_Single_Register =>
            R.Quantity_Field = 1,
          when Write_Multiple_Registers =>
            R.Quantity_Field in 1 .. 123,
          when others => False)
       and then Natural (R.Address_Field) +
                Natural (R.Quantity_Field) <= 65_536);
end Warden.Modbus;
