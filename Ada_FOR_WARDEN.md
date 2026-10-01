# Ada concepts you need for Warden

You do not need to know all of Ada before working on this project.

You do need to recognize a few things that appear everywhere in the code.

---

## Packages: `.ads` and `.adb`

Ada code is usually organized into **packages**.

A package often has two files:

```text
warden-gate.ads
warden-gate.adb
```

The `.ads` file is the **specification**.

It tells other code what the package provides:

```ada
package Warden.Gate is

   procedure Inspect (...);

end Warden.Gate;
```

The `.adb` file is the **body**.

It contains the implementation:

```ada
package body Warden.Gate is

   procedure Inspect (...) is
   begin
      ...
   end Inspect;

end Warden.Gate;
```

A useful way to think about it is:

```text
.ads = interface / contract
.adb = implementation
```

When trying to understand a package, read the `.ads` first.

It tells you what the package is supposed to do before you get lost in how it does it.

---

## `with` means "I use this package"

At the top of an Ada file you will see things like:

```ada
with Warden.Modbus;
with Warden.Policy;
```

This means the current unit depends on those packages.

It is roughly similar to an `import` in Python or an `#include` in C, although Ada's rules are stricter.

---

## Types matter a lot in Ada

In many languages, programmers use integers for almost everything.

Ada encourages you to say what an integer actually represents.

Instead of:

```ada
Address : Integer;
```

we can have:

```ada
type Register_Address is range 0 .. 65_535;
```

Now an address is a different concept from some unrelated integer.

This helps both humans and the compiler.

For Warden, expect to see types for things such as:

```text
bytes
register addresses
function codes
quantities
verdicts
approved requests
```

This is intentional.

---

## A `subtype` adds a restriction

Suppose Modbus allows a read quantity only between 1 and 125.

Instead of accepting every `U16` value, Ada can express that directly:

```ada
subtype Read_Quantity is U16 range 1 .. 125;
```

`Read_Quantity` is still based on `U16`, but only values from 1 through 125 are valid.

So:

```ada
Q : Read_Quantity := 10;
```

is fine.

But:

```ada
Q : Read_Quantity := 500;
```

is not.

This is one of the main ideas of the project:

> Put rules in the types when possible instead of scattering checks throughout the code.

---

## `private` means "you may use it, but you may not see inside it"

You will see:

```ada
type Approved is private;
```

This is especially important in Warden.

Other packages know that the type `Approved` exists, but they cannot see its internal representation.

They cannot do something like:

```ada
Request.Valid := True;
```

because they do not even know whether a field named `Valid` exists.

Only `Warden.Gate` knows how an `Approved` value is built.

This lets the package protect an important rule:

```text
Approved values come from the gate.
```

---

## Procedure parameters have modes

Ada tells you how each parameter is used.

For example:

```ada
procedure Inspect
  (Input   : Byte_Array;
   Result  : out Verdict;
   Request : out Approved);
```

`Input` has no explicit mode, so it is an `in` parameter.

That means the procedure receives it as input.

```ada
Input : Byte_Array
```

Think:

```text
procedure reads this
```

An `out` parameter is produced by the procedure:

```ada
Result : out Verdict
```

Think:

```text
procedure writes the answer here
```

So:

```ada
procedure Inspect
  (Input   : Byte_Array;
   Result  : out Verdict;
   Request : out Approved);
```

means:

```text
INPUT:
    raw bytes

OUTPUT:
    verdict
    approved request
```

You may also see `in out`, meaning the procedure both reads and modifies the value.

---

## Functions return a value

An Ada function looks like:

```ada
function Is_Valid (Request : Approved) return Boolean;
```

You can read this almost as English:

```text
function Is_Valid
takes an Approved request
returns True or False
```

It can then be used in an expression:

```ada
if Is_Valid (Request) then
   ...
end if;
```

---

## `Pre` means "this must already be true"

SPARK uses contracts.

For example:

```ada
procedure Forward (Request : Gate.Approved)
with
  Pre => Gate.Is_Valid (Request);
```

The `Pre` condition means:

> Before calling `Forward`, `Request` must be valid.

So this is not merely documentation.

SPARK can ask:

```text
Can you prove that Request is valid here?
```

If the answer is no, proof fails.

---

## `Post` means "this will be true afterwards"

For example:

```ada
procedure Inspect
  (Input   : Byte_Array;
   Result  : out Verdict;
   Request : out Approved)
with
  Post => Is_Valid (Request) = (Result = Accepted);
```

The `Post` condition describes what must be true after `Inspect` returns.

Here:

```text
Request is valid
if and only if
Result is Accepted
```

So if proof establishes:

```ada
Result = Accepted
```

it can also establish:

```ada
Is_Valid (Request)
```

That becomes important when the request is later passed to `Forward`.

---

## `=` in a contract is comparison

This line can be confusing at first:

```ada
Is_Valid (Request) = (Result = Accepted)
```

There are two comparisons here.

First:

```ada
Result = Accepted
```

asks whether the verdict is `Accepted`.

That produces a Boolean value:

```text
True or False
```

Then:

```ada
Is_Valid (Request) = (...)
```

compares two Boolean values.

So the whole expression means:

```text
Is_Valid(Request) and Result = Accepted
must always have the same truth value.
```

In plain English:

```text
The request is valid exactly when the result says Accepted.
```

---

## Ada uses `:=` for assignment

This:

```ada
Count := 10;
```

means:

```text
put 10 into Count
```

This:

```ada
Count = 10
```

means:

```text
is Count equal to 10?
```

That distinction is worth learning immediately.

```text
:=   assignment
=    comparison
```

---

## `if` is deliberately explicit

Ada writes conditionals like this:

```ada
if Result = Accepted then
   Wire.Forward (Request, Delivered);
else
   Journal.Refused (Result);
end if;
```

There are no braces.

The ending says exactly what is ending:

```ada
end if;
```

The same style appears elsewhere:

```ada
end loop;
end Inspect;
end Warden.Gate;
```

It can look verbose at first, but it makes larger code surprisingly easy to read.

---

## Arrays have explicit bounds

Warden works with byte arrays.

You may see loops like:

```ada
for I in Input'Range loop
   ...
end loop;
```

`Input'Range` means:

> the valid indexes of `Input`

So instead of assuming that an array starts at zero or manually calculating its last index, Ada lets the array tell you.

Related attributes you will see include:

```ada
Input'First
Input'Last
Input'Length
Input'Range
```

They mean:

```text
first valid index
last valid index
number of elements
all valid indexes
```

These are useful in SPARK because they reduce accidental out-of-bounds access.

---

## Range checks are real

Suppose:

```ada
subtype Byte is Integer range 0 .. 255;
```

Then this is valid:

```ada
B : Byte := 42;
```

but trying to put `300` into `B` violates the type's range.

Ada does not normally treat these ranges as comments.

They are part of the program.

SPARK can often prove that these checks can never fail.

That is one reason Ada types are used heavily in Warden.

---

## Enums are names, not magic numbers

A verdict might look like:

```ada
type Verdict is
  (Accepted,
   Invalid_Length,
   Invalid_Protocol,
   Unsupported_Function,
   Address_Not_Permitted);
```

Then the code says:

```ada
if Result = Invalid_Protocol then
   ...
end if;
```

instead of something like:

```ada
if Result = 3 then
   ...
end if;
```

For security code, named states are much easier to review.

---

## What SPARK is doing here

SPARK is not a different language.

It is a subset of Ada plus tools and rules that make formal reasoning possible.

For this project, the important distinction is:

```text
Ada compiler:
    Is this legal Ada?

SPARK prover:
    Can the contracts and safety properties be proven?
```

For example, the compiler can check that you passed an `Approved` value to:

```ada
Forward
```

SPARK can go further and check whether you proved:

```ada
Is_Valid (Request)
```

before making that call.

So throughout Warden, try to notice three levels:

```text
1. Does it compile?
2. Does it pass the tests?
3. Does it prove?
```

A good change should eventually satisfy all three.

---

## The reading strategy

When opening an unfamiliar Warden package, use this order:

```text
1. Read the .ads file.
2. Look at the types.
3. Look at Pre and Post contracts.
4. Ask what the package promises.
5. Only then read the .adb implementation.
```

For this project, start with:

```text
src/net/warden_main.adb
```

to understand the overall flow.

Then read:

```text
src/core/warden-gate.ads
src/core/warden-modbus.ads
src/core/warden-policy.ads
```

before diving into their bodies.

You do not need to understand every Ada feature immediately.

At first, concentrate on this path:

```text
bytes
  |
  v
Modbus.Decode
  |
  v
Policy.Permits
  |
  v
Gate.Inspect
  |
  v
Approved
  |
  v
Wire.Forward
```

If that flow is clear, you already understand the main architecture of Warden.
