package body Warden.Modbus with
  SPARK_Mode
is

   use type U16;

   --  Read a 16-bit big-endian integer at offset At_Offset.
   function Get_U16 (Raw : Byte_Array; At_Offset : Natural) return U16 is
     (Interfaces.Shift_Left (U16 (Raw (Raw'First + At_Offset)), 8)
      or U16 (Raw (Raw'First + At_Offset + 1)))
   with
     Pre => Raw'Length >= Min_Message and then At_Offset <= 4;

   ------------
   -- Decode --
   ------------

   function Decode (Raw : Byte_Array) return Fields is
     (Transaction   => Get_U16 (Raw, 0),
      Protocol      => Get_U16 (Raw, 2),
      Length        => Get_U16 (Raw, 4),
      Unit          => Raw (Raw'First + 6),
      Function_Code => Raw (Raw'First + 7));

end Warden.Modbus;
