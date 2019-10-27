# Serval SOSP'19 Tutorial

This repository contains the code for the Serval tutorial
at [SOSP'19](https://sosp19.rcs.uwaterloo.ca).

This tutorial is based on our SOSP'19 paper,
[Scaling symbolic evaluation for automated verification of systems code with Serval](https://unsat.cs.washington.edu/papers/nelson-serval.pdf).

It requires that you have the following prerequisite
tools installed:

- [Racket](https://download.racket-lang.org) (tested on 7.4)
- RISC-V gcc toolchain

Optionally, to run the toy monitor, you will
need the QEMU RISC-V emulator installed.

### Using Docker

The easiest way to follow this tutorial
is to use our provided [Docker image](https://cloud.docker.com/u/unsat/repository/docker/unsat/serval-tutorial-sosp19) to run
the code and verification.

If you have Docker installed, you can run
the image with:

```
docker run -it --rm unsat/serval-tutorial-sosp19:latest
```

This will drop you in to a shell in the tutorial directory
with all requisite tools installed. The image comes installed
with vim to let you view and edit files. Be careful, when
the container exits, all changes will be lost. If you want
to keep your changes, remove the `--rm` from the command
above; this will cause Docker to create a persistent container
with your local changes.

### Installing on Linux

The following will install the RISC-V toolchain
on Linux (tested on Ubuntu 19.04).

```
$ apt-get install git build-essential gdb-multiarch
$ apt-get install qemu-system-misc gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu
```

### Installing on macOS

You can install the RISC-V toolchain and Racket on
macOS using homebrew as follows:

```
$ brew tap riscv/riscv
$ brew install qemu riscv-tools
$ brew cask install racket
```

## Overview

- Toy security monitor
- Implementation
- Verification
  + State-machine refinement
    * Introducing a low-level bug
    * Introducing a semantic bug
  + Safety specification
    * Introducing a confidentiality bug
- Going further

## Project layout

`monitor/`: the implementation of the toy security
monitor we will verify.

`monitor/verif/`: the specification and verification
infrastructure for verification of the toy security monitor.

`serval/`: the Serval framework containing the RISC-V
interpreter, symbolic optimizations, and specification libraries.

## A toy security monitor

To demonstrate how to use Serval to verify a simple system,
we've implemented and specified a toy, security monitor-like
system on RISC-V. The security monitor has three system calls:


- `dict_get() -> long`
- `dict_set(long) -> void`
- `change_user(long) -> void`

The system state is an integer for the current user,
and a global array containing one integer per user (up to `MAXUSER`). `dict_get` and `dict_set` retrieve and set
the value in this array corresponding to the current user,
if the current user is less than `MAXUSER`. `change_user(x)`
changes the the current user to be `x`.

## Running the implementation

`monitor/kernel/` contains an implementation of a simple kernel
to test the features of the monitor. To run it on top of the toy security monitor,
run:

```
make CONFIG_VERIFICATION=0 -j4 -B qemu-monitor
```

The toy kernel sets a value, changes users, sets another value, then changes back to the original user. The expected output is as follows:

```
Hello from ToyMon!
Hello from kernel!
change_user(0)
dict_set(5)
dict_get() -> 5
change_user(3)
dict_set(2)
dict_get -> 2
change_user(0)
dict_get -> 5
```

Afterwards, run `make clean` to make sure your repository
is clean. Otherwise, verification may fail due to the
presence of debugging output caused by `CONFIG_VERIFICATION=0`.

## Verification

We will use Serval to verify the toy security monitor in
two parts. In this section we will look at what
at the Rosette code for doing verification, and introduce
bugs into the system to see how they affect verification.

You can run all verification test cases with

```
make verify-monitor
```

### 1. State-machine refinement

The first step in verifying this toy security monitor
is to prove that the implementation is a state-machine
refinement of the specification.
This requires the developer to provide three components:

- Functional specification: an abstract description
of the state of the system and state-machine transition (system call).

- Abstraction function: a function that maps the low-level implementation state to the high-level
specification state.

- Representation invariant: any invariants of the implementation necessary to establish refinement; these
are assumed to hold on entry to each system call, and proven to hold after.

The functional specification for the toy monitor
is found in `monitor/verif/spec.rkt`.
The abstraction function and representation invariant
are found in `monitor/verif/impl.rkt`, in the
`abs-function` and `rep-invariant` functions, respectively.

The specification state contains the current user,
the dictionary, and the return value of the most
recent system call.

The abstraction function reads from memory the relevant
parts of the implementation, and wraps them into
a specification state.

The representation invariant states that the `mtvec`
and `mscratch` registers must be constant points
to the trap entry function and the security monitor stack,
respectively. This is required for the security monitor
to correctly handle system calls.

Given these components, we prove state-machine refinement
by showing the following: for any implementation state that
satisfies the representation invariant, and for any equivalent specification state, if we run the implementation of a system call and the specification of the system call, the results are equivalent and the representation invariant holds on the new implementation state.


#### Introducing a low-level bug

The implementation of `dict_get` in `monitor/monitor.c` checks if `current_user` is valid before using
it as an index into the array of values.

We can remove this check to see what happens in the refinement verification.
First, comment out the check in `monitor/monitor.c:sys_dict_get` as follows:

```c
long sys_dict_get(void)
{
    // if (current_user < MAXUSER)
        return dictionary[current_user];

    return -1;
}
```

Next, re-run the refinement verification with `make verify-monitor-refinement`.
Verification should fail in the "sys_dict_get refinement" test case, with the following output:

```
Running test "sys_dict_get refinement"
Low-level bug:
 Location: (bv #x000000008000346c 64)
 Message: "marray-path: offset (bvshl current_user$mcell$5 (bv #x0000000000000003 64)) not in bounds (bv #x0000000000000008 64)"
--------------------
sys_dict_get refinement
FAILURE
name:       check-unsat?
location:
  /Users/lukenels/repo/riscvisor/serval/serval/spec/refinement.rkt:47:4
params:     '((model
 [current_user$mcell$5 (bv #x0800000000000000 64)]))
--------------------
```

Serval reports various information to help debug
the issue.

First, it provides the location of the bug in the
form of a program counter in the monitor where
the issue occurs. In this case, the problem is at
`0x8000346c`. You can open `o.riscv64/monitor.c.asm`
to find this location to help you debug. In this case,
the problem comes from the fact that Serval cannot
prove that the address used in a load instruction
is in-bounds, indicating a buffer overflow:

```
    8000346c:	0007b783          	ld	a5,0(a5)
```

You can also use `addr2line` to convert the address
to a C source location to help debug the issue, e.g.,
`riscv64-unknown-elf-addr2line -e o.riscv64/monitor.elf 000000008000346c`. (Note, you may need to use `riscv64-linux-gnu-addr2line` depending on how you installed the toolchain.)



Serval also provides a message to help debug the root
cause of the issue, in this case, indicating
that the problem is a potentially out-of-bounds
memory array index.

Finally it provides a concrete state of the system
that will trigger the bug. In this case, the generated
counterexample is a state where the current user
is a very large value that will overflow the array:

```
[current_user$mcell$5 (bv #x0800000000000000 64)]
```

#### Introducing a semantic bug

In addition to proving that the implementation
is free of low-level bugs like buffer overflows,
Serval must prove that the implementation and
specification operations are equivalent.
We can test this by introducing a semantic bug in the
implementation that causes the behavior of the
implementation and specification to differ.

The bug we will introduce is to modify the `dict_set`
system call to not write the new value into the dictionary,
as follows:

```c
long sys_dict_set(long value)
{
    if (current_user < MAXUSER) {
        // dictionary[current_user] = value;
        return 0;
    }

    return -1;
}
```

Next, re-run verification with `make verify-monitor-refinement`.
This causes verification to fail with the following output:

```
Running test "sys_dict_set refinement"
Args: '(1)

spec state:
 retval: 0
 current-user: 0
 dict: '(1 0 0 0)

abs(impl state):
 retval: 0
 current-user: 0
 dict: '(0 0 0 0)
--------------------
```

Here, the test case prints the concrete arguments to `dict_set`
and resulting system state that demonstrate the bug.

### 2. Safety specification

State-machine refinement establishes that the system
implementation behaves like the specification.
While the specification is more abstract, it's still
possible to make the same mistake in the implementation
and the specification. To help catch bugs in the
specification, developers can write a _safety_
specification on top of the functional specification.

For the toy security monitor, we will use a simple
confidentiality property as our safety specification.
The goal is to show
that the return value of the `dict_get` system
call depends only on values observable by the
current user, i.e., that `dict_get` cannot read
values from other users.

We leave more complex properties, such as showing
that `dict_set` does not modify other users' data,
as exercises.

This safety property requires the developer to provide
an equivalence function, which defines when two
specification states appear equivalent to the
current user. We then prove confidentiality by showing
that, for any two states equivalent to the current user,
those states are still equivalent after executing
the `dict_get` system call specification.

The equivalence function and confidentiality definition
are located in `monitor/verif/safety.rkt`.
The equivalence relation states that two states
are equivalent if, in both of the states, the current
user is the same, the return value of the most recent
system call is the same, and the value in the dictionary
for the current user is the same.

#### Introducing a confidentiality bug

To test our safety specification, we will introduce
a bug in the specification of `dict_get` that reads
a value in the dictionary belonging to another user.

The functional specification for `dict_get` is located
in `monitor/verif/spec.rkt`. Like the implementation,
it retrieves the value of the current user and looks
up the value in the dictionary beloning to that user.
To violate confidentiality, we will change this function
to always return the value beloning to user 1, by
replacing the specification with the following:

```racket
(define (sys-dict-get st)
  (define current-user (state-current-user st))
  (define dict (state-dict st))

  (if (bvult current-user (bv constants:MAXUSER 64))
     ;; Changed current-user to (bv 1 64) here
     (set-state-retval! st (dict (bv 1 64)))
     (set-state-retval! st (bv -1 64))))
```

Next, re-run safety verification with
`make verify-monitor-safety`.

This should cause the "confidentiality sys-dict-get"
test case to fail with the following output:

```
Running test "confidentiality sys-dict-get"
Confidentiality violation:
Operation: #<procedure:sys-dict-get>
Arguments: '()

State 1:
 retval: 1
 current-user: 0
 dict: '(0 1 0 0)

State 2:
 retval: 0
 current-user: 0
 dict: '(0 0 0 0)
--------------------
confidentiality sys-dict-get
FAILURE
name:       check-unsat?
location:   safety.rkt:51:2
params:
  '((model
   [retval$0 (bv #x0000000000000000 64)]
   [current-user$0 (bv #x0000000000000000 64)]
   [dictionary$0 (fv (bitvector 64)~>(bitvector 64))]
   [retval$1 (bv #x0000000000000000 64)]
   [current-user$1 (bv #x0000000000000000 64)]
   [dictionary$1 (fv (bitvector 64)~>(bitvector 64))]))
--------------------
```

The test case prints some information to help
debug the confidentiality violation.
The output shows the two states after running
the `dict_get` system call. This represents
a confidentiality violation because the two states
are not equivalent to the current user (user 0),
in particular, because the return value does not match.
This happens because `dict_get` always returns the
value corresponding to user 1, which is not a value
observable to user 0, and thus may differ in the two
states.


## Going further

This example shows one way of using Serval's RISC-V verifier
to prove correct a simple system. If you're interested in the details,
you can look in the `serval/` directory to see how the verifiers
and optimizations are implemented; and even choose to extend a verifier
or implement a new one yourself.

For more details, you can look at the
[Serval SOSP'19 artifact](https://github.com/uw-unsat/serval-sosp19/), which contains
implementations and specifications of ports of previously verified systems CertiKOS and Komodo;
you can go there to see how more complex systems are verified.

The [Serval SOSP'19 paper](https://unsat.cs.washington.edu/papers/nelson-serval.pdf)
has more details on the techniques used in implementing Serval and retrofitting
existing systems for automated verification.