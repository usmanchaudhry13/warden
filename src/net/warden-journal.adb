with Ada.Text_IO;

package body Warden.Journal with
  SPARK_Mode => Off
is

   ----------
   -- Note --
   ----------

   procedure Note (Text : String) is
   begin
      Ada.Text_IO.Put_Line ("warden: " & Text);
      Ada.Text_IO.Flush;
   end Note;

end Warden.Journal;
