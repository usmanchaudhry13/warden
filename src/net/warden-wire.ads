--  The network side: two TCP connections and the bytes on them.
--
--     client  <---->  [ warden ]  <---->  controller
--
--  "Client" and not "operator" on purpose: the proxy sees a connection,
--  it does not know who is at the other end.
--
--  The spec is in SPARK so that the main program can be checked against
--  it. The body is not: it talks to the operating system (GNAT.Sockets).
--  It is kept small, because nothing proves it.

with Warden.Gate;
with Warden.Journal;

package Warden.Wire with
  SPARK_Mode,
  Abstract_State => (Network with External)
is

   procedure Open (Ready : out Boolean) with
     Global => (In_Out => (Network, Journal.Output));
   --  Start listening. Ready is False if the port cannot be used.

   procedure Wait_For_Client (Connected : out Boolean) with
     Global => (In_Out => Network);
   --  Block until a client connects, then connect to the controller.
   --  Connected is False if the controller cannot be reached; the client
   --  is dropped in that case.

   procedure Read_Request
     (Data   : out Chunk;
      Length : out Natural;
      Alive  : out Boolean)
   with
     Global => (In_Out => Network),
     Post   => (if Alive then Length in 1 .. Max_Read else Length = 0);
   --  One read from the client: Data (0 .. Length - 1). Alive is False
   --  when the client is gone.
   --
   --  OPEN: TCP delivers a stream of bytes, not messages. One read can
   --  return half a request, or two requests. The seed ignores that.
   --  Also: this call waits for as long as the client stays silent.
   --  See docs/TRAIL.md, stops 3 and 6.

   procedure Forward
     (Request   : Gate.Approved;
      Delivered : out Boolean)
   with
     Global => (In_Out => Network),
     Pre    => Gate.Is_Valid (Request);
   --  Send the approved bytes to the controller, wait for its answer and
   --  hand that answer to the client. Delivered is False if either side
   --  is gone.
   --
   --  This is the only way anything reaches the controller.
   --
   --  OPEN: the answer goes back to the client unread.

   procedure Hang_Up with
     Global => (In_Out => Network);
   --  Close both connections.

end Warden.Wire;
