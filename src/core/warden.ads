--  Warden: a proxy that stands between an operator and an industrial
--  controller, and only lets through the Modbus/TCP requests it can
--  vouch for.
--
--  This root package holds the few basic types everything else shares.
--  Start reading in ARCHITECTURE.md, then src/net/warden_main.adb.

with Interfaces;

package Warden with
  Pure,
  SPARK_Mode
is

   subtype Byte is Interfaces.Unsigned_8;
   subtype U16 is Interfaces.Unsigned_16;

   type Byte_Array is array (Natural range <>) of Byte;

   --  The most bytes we take from the network in one read. Larger than
   --  the largest legal Modbus/TCP message (260 bytes), so that "too
   --  long" is something we can see instead of something cut off.
   Max_Read : constant := 512;

   subtype Chunk is Byte_Array (0 .. Max_Read - 1);

end Warden;
