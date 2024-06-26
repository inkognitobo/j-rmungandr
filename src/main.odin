package main

import "core:c"
import "core:container/queue"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import SDL "vendor:sdl2"


TRACK_MEM :: #config(TRACK_MEM, false) // Report memory leaks?
RESIZABLE :: #config(RESIZABLE, false) // Window resizable?

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

RESOLUTION :: Vec2i{144, 144}

CELL_SIZE :: 16

NS_PER_SEC :: 1_000_000_000

Vec2i :: [2]i32

// Direction names.
Direction :: enum {
    UP,
    DOWN,
    RIGHT,
    LEFT,
}

// Direction defined as 2-dimensional vector.
DirectionVec := [Direction]Vec2i {
    .UP    = {0, 1},
    .DOWN  = {0, -1},
    .RIGHT = {1, 0},
    .LEFT  = {-1, 0},
}

// Player entitiy.
Snake :: struct {
    direction: Direction,
    body:      queue.Queue(Vec2i),
    fed:       bool,
}

// Power-up entity.
Apple :: struct {
    using pos: Vec2i,
}

// Contains internal game state.
State :: struct {
    // SDL2.
    window:      ^SDL.Window,
    renderer:    ^SDL.Renderer,
    texture:     ^SDL.Texture,
    // Window.
    window_size: Vec2i,
    // Time.
    time:        struct {
        last_second, last_frame, last_tick: u64,
        frames, fps:                        int,
        delta:                              f64,
    },
    // Global entities.
    snake:       Snake,
    apples:      [dynamic]Apple,
}

/*
Update the snakes direction to `dir`.
If `dir` is the exact opposite of the old direction, do nothing. 
*/
update_snake_direction :: proc(state: ^State, dir: Direction) {
    new := DirectionVec[dir]
    old := DirectionVec[state.snake.direction]

    // Only update if new direction is not exact opposite of old direction.
    state.snake.direction = dir if new != old * (-1) else state.snake.direction
}

/*
Update internal game state.
Called every `xxx` nanoseconds, where `xxx` is specified in the main loop.

Returns:
- `ok`: `true` if no errors occured, `false` otherwise.
*/
update :: proc(state: ^State) -> (ok: bool) {
    // Move snake.
    old_head := queue.get(&state.snake.body, 0)
    new_head := old_head + DirectionVec[state.snake.direction] * CELL_SIZE
    new_head.x = new_head.x %% RESOLUTION.x
    new_head.y = new_head.y %% RESOLUTION.y
    if ok, err := queue.push_front(&state.snake.body, new_head); !ok {
        fmt.eprintfln("could not push: %v", err)
        return
    }
    if !state.snake.fed {
        if tail, ok := queue.pop_back_safe(&state.snake.body); !ok {
            fmt.eprintfln("could not pop")
            return
        }
    }
    state.snake.fed = false

    // Check collision with itself.
    for i in 1 ..< state.snake.body.len {
        if queue.get(&state.snake.body, i) == new_head {
            fmt.println("[DEBUG] Collision: Snake!")
            return false
        }
    }

    // Check collision with apple.
    #reverse for apple, i in state.apples {
        if apple.pos == new_head {
            fmt.println("[DEBUG] Collision: Apple!")
            unordered_remove(&state.apples, i)
            state.snake.fed = true
        }
    }

    // Spawn new apple.
    spawn_apple: if rand.float32() < 0.125 {
        apple := Apple {
            pos = (((Vec2i{rand.int31(), rand.int31()}) %
                    (RESOLUTION / CELL_SIZE)) *
                CELL_SIZE),
        }
        // Check if the apple would spawn inside snake.
        for i in 1 ..< state.snake.body.len {
            if queue.get(&state.snake.body, i) == apple.pos {
                break spawn_apple
            }
        }
        append(&state.apples, apple)
        fmt.printfln("[DEBUG] New apple: %v", apple)
    }

    return true
}

/*
Render the screen to reflect internal game state.
Called for every frame, i.e. approximately `FPS` times per second.

Returns:
- `ok`: `true` if no errors occured, `false` otherwise.
*/
render :: proc(state: ^State) -> (ok: bool) {
    using state

    // Clear renderer.
    if ok := SDL.SetRenderDrawColor(renderer, 0x28, 0x28, 0x28, 0xFF);
       ok != 0 {return}
    if ok := SDL.RenderClear(renderer); ok != 0 {return}


    // Render to backbuffer.
    if ok := SDL.SetRenderTarget(renderer, texture); ok != 0 {return}

    // Clear backbuffer.
    if ok := SDL.SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF);
       ok != 0 {return}
    if ok := SDL.RenderClear(renderer); ok != 0 {return}

    // Render snake body.
    for i in 0 ..< snake.body.len {
        if i == 0 {
            if ok := SDL.SetRenderDrawColor(renderer, 0xFF, 0x00, 0x00, 0xFF);
               ok != 0 {return}
        } else {
            if ok := SDL.SetRenderDrawColor(renderer, 0x88, 0x00, 0x00, 0xFF);
               ok != 0 {return}
        }
        pos := queue.get(&snake.body, i)
        if ok := SDL.RenderFillRect(
            renderer,
            &SDL.Rect{pos.x + 1, pos.y + 1, CELL_SIZE - 2, CELL_SIZE - 2},
        ); ok != 0 {return}
    }

    // Render apples.
    if ok := SDL.SetRenderDrawColor(renderer, 0x00, 0xFF, 0x00, 0xFF);
       ok != 0 {return}
    for apple in apples {
        if ok := SDL.RenderFillRect(
            renderer,
            &SDL.Rect{apple.x + 1, apple.y + 1, CELL_SIZE - 2, CELL_SIZE - 2},
        ); ok != 0 {return}
    }

    // Detach texture.
    if ok := SDL.SetRenderTarget(renderer, nil); ok != 0 {return}

    // Draw texture to screen.
    // Flip vertically, i.e. {0, 0} is in the bottom left corner.
    //
    // Setting source and destination to nil means stretching the texture
    // over the entire screen.
    //
    // To keep the ratio of the resolution, We need to scale the destination 
    // rect such that the height is at 100% of the resolution and
    // then re-center it horizontally.
    screen_scale := f32(window_size.y) / f32(RESOLUTION.y)
    if ok := SDL.RenderCopyEx(
        renderer,
        texture,
        &(SDL.Rect){0, 0, RESOLUTION.x, RESOLUTION.y},
        &(SDL.Rect) {
            (window_size.x - i32(f32(RESOLUTION.x) * screen_scale)) / 2,
            0,
            i32(f32(RESOLUTION.x) * screen_scale),
            window_size.y,
        },
        0.0,
        nil,
        .VERTICAL,
    ); ok != 0 {return}

    SDL.RenderPresent(renderer)

    return true
}

/*
Initialise the SDL2 library and relevant structs.

Returns:
- `ok`: `true` if no errors occured, `false` otherwise.
*/
sdl_init :: proc(state: ^State) -> (ok: bool) {
    // Initialise SDL2.
    if err := SDL.Init({}); err != 0 {
        fmt.eprintfln("could not instantiate SDL: %v", SDL.GetError())
        return false
    }

    // Create window.
    if state.window = SDL.CreateWindow(
        "Jörmungandr",
        SDL.WINDOWPOS_UNDEFINED,
        SDL.WINDOWPOS_UNDEFINED,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        {.RESIZABLE} when RESIZABLE else {},
    ); state.window == nil {
        fmt.eprintfln("could not create window: %v", SDL.GetError())
        return false
    }

    // Create renderer.
    if state.renderer = SDL.CreateRenderer(
        state.window,
        0,
        {.ACCELERATED, .PRESENTVSYNC},
    ); state.renderer == nil {
        fmt.eprintfln("could not create renderer: %v", SDL.GetError())
        return false
    }

    // Create backbuffer.
    if state.texture = SDL.CreateTexture(
        state.renderer,
        SDL.PixelFormatEnum.ARGB8888,
        .TARGET,
        c.int(RESOLUTION.x),
        c.int(RESOLUTION.y),
    ); state.texture == nil {
        fmt.eprintfln("could not create texture: %v", SDL.GetError())
        return false
    }

    return true
}

main :: proc() {
    // Enabled using `-define:TRACK_MEM=true` CLI option.
    when TRACK_MEM {
        tracking_allocator: mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracking_allocator, context.allocator)
        context.allocator = mem.tracking_allocator(&tracking_allocator)
        defer {
            for _, leak in tracking_allocator.allocation_map {
                fmt.eprintf("%v leaked %m\n", leak.location, leak.size)
            }
            for bad_free in tracking_allocator.bad_free_array {
                fmt.eprintf(
                    "%v allocation %p was freed badly\n",
                    bad_free.location,
                    bad_free.memory,
                )
            }
            mem.tracking_allocator_destroy(&tracking_allocator)
        }
    }

    // Initialise state.
    state: State
    defer delete(state.apples)

    // Initialise SDL2.
    if ok := sdl_init(&state); !ok {return}
    defer {
        SDL.DestroyWindow(state.window)
        SDL.DestroyRenderer(state.renderer)
        SDL.DestroyTexture(state.texture)
        SDL.Quit()
    }

    // Initialise time.
    state.time.last_second = SDL.GetPerformanceCounter()

    // Initialise snake.
    state.snake.direction = Direction(rand.uint64() % len(Direction))
    if err := queue.init(&state.snake.body); err != nil {
        fmt.eprintfln("could not initialise queue: %v", err)
        return
    }
    defer queue.destroy(&state.snake.body)
    if ok, err := queue.push_front(&state.snake.body, Vec2i{0, 1} * CELL_SIZE);
       !ok {
        fmt.eprintfln("could not push: %v", err)
        return
    }

    loop: for {
        // Update window size.
        w, h: c.int
        SDL.GetWindowSize(state.window, &w, &h)
        state.window_size = Vec2i{w, h}

        // Compute FPS and delta time.
        now := SDL.GetPerformanceCounter()
        state.time.delta =
            f64(now - state.time.last_frame) /
            f64(SDL.GetPerformanceFrequency())
        state.time.frames += 1
        state.time.last_frame = now
        if now - state.time.last_second > SDL.GetPerformanceFrequency() {
            state.time.fps = state.time.frames
            state.time.frames = 0
            state.time.last_second = now
            fmt.printfln(
                "[DEBUG] FPS: %v, delta time: %.9f",
                state.time.fps,
                state.time.delta,
            )
        }

        // Event loop.
        event: SDL.Event
        for SDL.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break loop
            case .KEYDOWN:
                #partial switch event.key.keysym.sym {
                case .LEFT, .a, .h:
                    update_snake_direction(&state, .LEFT)
                case .DOWN, .s, .j:
                    update_snake_direction(&state, .DOWN)
                case .UP, .w, .k:
                    update_snake_direction(&state, .UP)
                case .RIGHT, .d, .l:
                    update_snake_direction(&state, .RIGHT)
                }
            }
        }

        if f64(now - state.time.last_tick) / NS_PER_SEC >= 0.75 {
            state.time.last_tick = now
            if ok := update(&state); !ok {return}
        }

        if ok := render(&state); !ok {
            fmt.eprintfln("could not render: %v", SDL.GetError())
        }
    }
}
