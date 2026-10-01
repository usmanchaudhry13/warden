--  Where the proxy listens and where the controller is.
--
--     warden --listen 5021 --controller 5020
--
--  Both are TCP ports on this machine (127.0.0.1). The values above are
--  the defaults.

package Warden.Settings is

   subtype Port is Positive range 1 .. 65_535;

   function Listen_Port return Port;
   --  Clients (the operator, or anyone else) connect here.

   function Controller_Port return Port;
   --  The proxy connects there, to the real controller.

end Warden.Settings;
