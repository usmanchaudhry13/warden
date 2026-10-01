with Ada.Streams;  use Ada.Streams;
with GNAT.Sockets; use GNAT.Sockets;

with Warden.Settings;

package body Warden.Wire with
  SPARK_Mode => Off
is

   Listener   : Socket_Type := No_Socket;
   Client     : Socket_Type := No_Socket;
   Controller : Socket_Type := No_Socket;

   procedure Close (S : in out Socket_Type) is
   begin
      if S /= No_Socket then
         begin
            Close_Socket (S);
         exception
            when Socket_Error =>
               null;
         end;
         S := No_Socket;
      end if;
   end Close;

   --  Send_Socket may send only part of what it is given.
   procedure Send_All (S : Socket_Type; Data : Stream_Element_Array) is
      First : Stream_Element_Offset := Data'First;
      Last  : Stream_Element_Offset;
   begin
      while First <= Data'Last loop
         Send_Socket (S, Data (First .. Data'Last), Last);
         First := Last + 1;
      end loop;
   end Send_All;

   ----------
   -- Open --
   ----------

   procedure Open (Ready : out Boolean) is
   begin
      Create_Socket (Listener);
      Set_Socket_Option (Listener, Socket_Level, (Reuse_Address, True));
      --  This machine only: the proxy is not reachable from the network.
      Bind_Socket
        (Listener,
         (Family => Family_Inet,
          Addr   => Loopback_Inet_Addr,
          Port   => Port_Type (Settings.Listen_Port)));
      Listen_Socket (Listener);
      Journal.Note
        ("listening on port" & Settings.Listen_Port'Image
         & ", controller on port" & Settings.Controller_Port'Image);
      Ready := True;
   exception
      when Socket_Error =>
         Close (Listener);
         Ready := False;
   end Open;

   ---------------------
   -- Wait_For_Client --
   ---------------------

   procedure Wait_For_Client (Connected : out Boolean) is
      Peer : Sock_Addr_Type;
   begin
      Connected := False;
      Accept_Socket (Listener, Client, Peer);
      Create_Socket (Controller);
      Connect_Socket
        (Controller,
         (Family => Family_Inet,
          Addr   => Loopback_Inet_Addr,
          Port   => Port_Type (Settings.Controller_Port)));
      Connected := True;
   exception
      when Socket_Error =>
         Hang_Up;
   end Wait_For_Client;

   ------------------
   -- Read_Request --
   ------------------

   procedure Read_Request
     (Data   : out Chunk;
      Length : out Natural;
      Alive  : out Boolean)
   is
      Buffer : Stream_Element_Array (1 .. Max_Read);
      Last   : Stream_Element_Offset;
   begin
      Data := (others => 0);
      Length := 0;
      Alive := False;

      Receive_Socket (Client, Buffer, Last);

      if Last >= Buffer'First then
         for I in Buffer'First .. Last loop
            Data (Natural (I - Buffer'First)) := Byte (Buffer (I));
         end loop;
         Length := Natural (Last - Buffer'First + 1);
         Alive := True;
      end if;
   exception
      when Socket_Error =>
         Length := 0;
         Alive := False;
   end Read_Request;

   -------------
   -- Forward --
   -------------

   procedure Forward
     (Request   : Gate.Approved;
      Delivered : out Boolean)
   is
      Message : constant Byte_Array := Gate.Bytes (Request);
      Output  : Stream_Element_Array (1 .. Message'Length);
      Answer  : Stream_Element_Array (1 .. Max_Read);
      Last    : Stream_Element_Offset;
   begin
      Delivered := False;

      for I in Message'Range loop
         Output (Stream_Element_Offset (I - Message'First) + 1) :=
           Stream_Element (Message (I));
      end loop;
      Send_All (Controller, Output);

      Receive_Socket (Controller, Answer, Last);

      if Last >= Answer'First then
         Send_All (Client, Answer (Answer'First .. Last));
         Delivered := True;
      end if;
   exception
      when Socket_Error =>
         Delivered := False;
   end Forward;

   -------------
   -- Hang_Up --
   -------------

   procedure Hang_Up is
   begin
      Close (Client);
      Close (Controller);
   end Hang_Up;

end Warden.Wire;
