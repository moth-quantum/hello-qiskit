# Hello Qiskit

A Godot 4 port of the *Hello Qiskit* puzzle game from the [Qiskit Textbook](https://github.com/Qiskit/textbook).

*Hello Qiskit* is a sister project of [Hello Quantum](https://helloquantum.mybluemix.net/), the quantum puzzle app developed by the University of Basel and IBM. Both games teach quantum computing through a visual representation of two-qubit states as Pauli expectation values arranged in a diamond lattice. Each puzzle asks the player to transform the state using quantum gates — X, Z, H, CNOT, and CZ — until the displayed values match a target configuration.

## Quantum engine

Gate simulation uses [MicroMoth](https://github.com/moth-quantum/MicroMoth), a lightweight statevector simulator written in GDScript.

## Licence

This project is licensed under the [Apache License 2.0](LICENSE), consistent with the original Hello Qiskit source.
