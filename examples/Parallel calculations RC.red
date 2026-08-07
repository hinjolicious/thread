Red [
    Title: "Parallel Calculation - Custom THREAD Scheduler & Channel"
	Author: "hinjolicious"
	Credits: "Gemini"
]

#include %../thread.red

;; --- 1. Incremental Factorizer Task Factory ---
;; Returns an inner task object compatible with THREAD/spawn.
;; Yields 'continue to keep checking time-slice budget, and 'finished when complete.
make-factor-task: func [num [integer! float!] out-channel [object!]] [
    object [
        target: num
        temp:   num
        d:      2
        step:   1
        factors: copy []
        chan:   out-channel
        
        task-func: func [] [
            either (d * d) <= temp [
                ; Trial division loop step
                while [0 = (temp % d)] [
                    append factors d
                    temp: temp / d
                ]
                d: d + step
                step: 2  ; Switch from checking 2 to odd numbers (3, 5, 7...)
                
                'continue ; Yield control back to step-func to evaluate time-slice budget
            ][
                ; Loop complete, handle remaining prime factor if > 1
                if temp > 1 [append factors temp]
                
                ; Send result [number [factors]] to output channel
                chan/put reduce [target factors]
                
                'finished ; Signal thread completion
            ]
        ]
    ]
]

result-chan: none

;; --- 2. Parallel Factorization Pipeline using THREAD ---
parallel-factorize: func [numbers [block!] /local decompositions] [
    THREAD/reset
    
    ; Create a channel to hold all output results
    result-chan: make-channel length? numbers
    
    ; Spawn a thread task for each candidate number (5ms time slice per tick)
    foreach num numbers [
        id: to-word rejoin ["task-" num]
        THREAD/spawn id 00:00:00.001 make-factor-task num result-chan
    ]
    
    ; Start scheduler execution loop until all tasks reach 'done state
    THREAD/run
    
    ; Drain result-chan into a block
    decompositions: make block! length? numbers
    while [not result-chan/ch-empty?] [
        append/only decompositions result-chan/get
    ]
    
    decompositions
]

;; --- 3. Search Function for Largest Minimal Factor ---
find-largest-min-factor: func [decompositions [block!]] [
    best-number:     none
    best-min-factor: -1
    best-factors:    none
    
    foreach entry decompositions [
        num:     first entry
        factors: second entry
        
        unless empty? factors [
            ; Prime factors are checked in ascending order,
            ; so the first item is guaranteed to be the minimal prime factor.
            min-factor: first factors
            
            if min-factor > best-min-factor [
                best-min-factor: min-factor
                best-number:     num
                best-factors:    factors
            ]
        ]
    ]
    
    reduce [best-number best-min-factor best-factors]
]

;; --- Demonstration ---

numbers: [
    112272537195293
    112582718962171
    112272537095293
    115280098190773
    115797840077099
    1099726829285419
]

print "=== Running Scheduler ==="
decompositions: parallel-factorize numbers

print "^/=== Task Telemetry Report ==="
foreach [id tsk] THREAD/tasks [ probe THREAD/task-telemetry tsk ]
print "^/=== THREAD Telemetry Report ==="
probe THREAD/telemetry
print "^/=== Channel Telemetry Report ==="
probe result-chan/telemetry

print "^/=== Search Results ==="
selection: find-largest-min-factor decompositions
winner:    first selection
min-p:     second selection
all-p:     third selection

print ["Number with largest minimal prime factor:" winner]
print ["Minimal prime factor:" min-p]
print ["Full prime decomposition:" mold all-p]