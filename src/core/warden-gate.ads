--  The gate: the one place that decides whether a request goes through.
--
--  The design rests on one idea. To send anything to the controller you
--  must hand Warden.Wire.Forward an Approved value. Approved is a private
--  type, and the only code that can make a valid one is Inspect, in this
--  package's body. So "nothing reaches the controller unless it passed
--  the gate" is not a convention the team has to remember: the compiler
--  and the prover enforce it.
--
--  There is a second half to the idea. What goes to the controller is
--  not the bytes the client sent: it is the bytes stored in the Approved
--  value, and the gate is the one that writes them.
--
--  Inspect is a pure function of bytes: it touches no socket. That is
--  what makes it provable, and easy to reason about.

with Warden.Modbus;

package Warden.Gate with
  SPARK_Mode
is

   type Verdict is
     (Accepted,
      Too_Short,
      Too_Long,
      Bad_Protocol,
      Denied);
   --  OPEN: one value per reason to refuse a request. The seed knows few.
   --  The gauntlet (tools/gauntlet.py) shows what still gets through.

   type Approved is private;
   --  A request that passed every check, ready to be sent.

   function Is_Valid (A : Approved) return Boolean;

   function Bytes (A : Approved) return Byte_Array with
     Pre  => Is_Valid (A),
     Post => Bytes'Result'First = 0
             and then Bytes'Result'Length in
               Modbus.Min_Message .. Modbus.Max_Message;
   --  What will be written to the controller.

   procedure Inspect
     (Input   : Byte_Array;
      Result  : out Verdict;
      Request : out Approved)
   with
     Global => null,
     Pre    => Input'First = 0 and then Input'Last < Max_Read,
     Post   => Is_Valid (Request) = (Result = Accepted);
   --  Input is what one read from the client's connection returned.
   --
   --  OPEN: the postcondition above says little. Once the checks exist,
   --  it can say exactly what "Accepted" guarantees. That sentence is
   --  the security claim of the whole project.

private

   subtype Message_Length is Natural range 0 .. Modbus.Max_Message;

   type Approved is record
      Valid  : Boolean := False;
      Length : Message_Length := 0;
      Data   : Byte_Array (0 .. Modbus.Max_Message - 1) := (others => 0);
   end record;

   function Is_Valid (A : Approved) return Boolean is
     (A.Valid and then A.Length >= Modbus.Min_Message);

   function Bytes (A : Approved) return Byte_Array is
     (A.Data (0 .. A.Length - 1));

end Warden.Gate;
