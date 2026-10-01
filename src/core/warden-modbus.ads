--  Modbus/TCP vocabulary: the shape of a message on the wire.
--
--  One message (an "ADU") is a 7 byte header followed by the request
--  itself (the "PDU"). Integers are big-endian. See docs/MODBUS.md.
--
--     offset  size  field
--          0     2  transaction id   chosen by the client, echoed back
--          2     2  protocol id      always 0 for Modbus
--          4     2  length           number of bytes that follow this field
--          6     1  unit id          which device behind a gateway
--          7     1  function code    what is asked: read, write...
--          8     n  data             depends on the function code
--
--  This package turns raw bytes into typed fields. Nothing else. It does
--  not decide whether a request is acceptable: see Warden.Gate.
--
--  The bytes come from the network, so treat every one as hostile.

package Warden.Modbus with
  Pure,
  SPARK_Mode
is

   Header_Size : constant := 7;
   Min_Message : constant := Header_Size + 1;     --  header + function code
   Max_Message : constant := Header_Size + 253;   --  260, fixed by the spec

   --  The function codes the pumping station uses (docs/PLANT.md).
   Read_Coils               : constant Byte := 1;
   Read_Discrete_Inputs     : constant Byte := 2;
   Read_Holding_Registers   : constant Byte := 3;
   Read_Input_Registers     : constant Byte := 4;
   Write_Single_Coil        : constant Byte := 5;
   Write_Single_Register    : constant Byte := 6;
   Write_Multiple_Registers : constant Byte := 16;
   --  OPEN: these are loose numbers, and any other byte value can arrive
   --  too. Once a message has been checked, what type should carry "one
   --  of the functions we handle"? See docs/TRAIL.md, stop 4.

   type Fields is record
      Transaction   : U16;
      Protocol      : U16;
      Length        : U16;
      Unit          : Byte;
      Function_Code : Byte;
   end record;
   --  OPEN: the seed decodes the header and the function code only.
   --  Addresses, quantities and values are in the bytes that follow, and
   --  nothing looks at them yet.

   function Decode (Raw : Byte_Array) return Fields with
     Global => null,
     Pre    => Raw'Length >= Min_Message;
   --  The fields of the message that starts at Raw'First.

end Warden.Modbus;
