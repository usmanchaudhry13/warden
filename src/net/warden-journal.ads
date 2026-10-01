--  What the proxy says about what it does.
--
--  Every line starts with "warden:" and goes to standard output.
--
--  OPEN: this is a print statement, not an audit trail. After an
--  incident, what would you need to find in here, and could you trust
--  it? See docs/TRAIL.md, stop 6.

package Warden.Journal with
  SPARK_Mode,
  Abstract_State =>
    (Output with External => (Async_Readers, Effective_Writes)),
  Initializes    => Output
is

   procedure Note (Text : String) with
     Global => (In_Out => Output);

end Warden.Journal;
