--  The proxy's main program.
--
--  Read this file first. It is the whole proxy on one screen: take what a
--  client sent, ask the gate, forward only what the gate approved.
--
--  Everything it prints starts with "warden:".

with Warden.Gate;
with Warden.Journal;
with Warden.Wire;

procedure Warden_Main with
  SPARK_Mode
is
   use Warden;

   Ready     : Boolean;
   Connected : Boolean;
   Alive     : Boolean;
   Delivered : Boolean;

   Data    : Chunk;
   Length  : Natural;
   Result  : Gate.Verdict;
   Request : Gate.Approved;
begin
   Wire.Open (Ready);

   if not Ready then
      Journal.Note ("cannot listen (is the port already in use?)");
      return;
   end if;

   --  OPEN: one client at a time. While this one is connected, nobody
   --  else is served, and nothing limits how long it stays or how fast
   --  it talks. See docs/TRAIL.md, stop 6.
   loop
      Wire.Wait_For_Client (Connected);

      if Connected then
         Journal.Note ("client connected");

         loop
            Wire.Read_Request (Data, Length, Alive);
            exit when not Alive;

            Gate.Inspect (Data (0 .. Length - 1), Result, Request);

            Journal.Note
              ("request of" & Length'Image & " bytes, verdict="
               & Result'Image);

            --  OPEN: a refused request ends the connection without a
            --  word. Is that the right answer for every verdict? What
            --  does the operator's screen show when it happens?
            exit when not Gate.Is_Valid (Request);

            Wire.Forward (Request, Delivered);
            exit when not Delivered;
         end loop;

         Wire.Hang_Up;
         Journal.Note ("client disconnected");
      else
         Journal.Note ("controller unreachable, client dropped");
      end if;
   end loop;
end Warden_Main;
