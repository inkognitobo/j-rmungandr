# jörmungandr

In Norse mythology, Jörmungandr (_Old Norse: Jǫrmungandr, lit. "the Vast 'gand'" [...]_), also known as the Midgard Serpent or World Serpent (_Old Norse: Miðgarðsormr_), 
is an unfathomably large sea serpent or worm who dwells in the world sea, encircling the Earth (Midgard) and biting his own tail, an example of an ouroboros
([1](https://en.wikipedia.org/wiki/J%C3%B6rmungandr)).

What a fantastic name for a completely original, a giant serpent involving game concept programmed in [Odin](https://odin-lang.org/) - definitely not "snake".

**Features:**

- no scores and definitely no scoreboards.
- no music / sound effects.
- crashes on game-over.
- snek.

## Run

Ensure you have an up-to-date Odin installation (refer to [Getting Started](https://odin-lang.org/docs/install/)).
Compile to `build/` directory and run:

```
mkdir build
odin run src/ -out=build/jörmungandr -define:TRACK_MEM=true -define:RESIZABLE=false
```
