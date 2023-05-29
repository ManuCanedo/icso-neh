using Dates
using Profile
using ProfileSVG

include("inputs.jl")
include("pyarray.jl")
include("objects.jl")

t = 0.005

function insertJobIntoSequence(solution, inputs, k, kJob)
    n = length(solution.jobs)
    # Create earliest, tail, and relative completion times structures
    e = toPythonLikeArray(zeros(n + 2, inputs.nMachines + 1))
    q = toPythonLikeArray(zeros(n + 2, inputs.nMachines + 1))
    f = toPythonLikeArray(zeros(n + 2, inputs.nMachines + 1))
    # Compute earliest, tail, and relative completion times values
    for i = 1:n+1
        for j = 1:inputs.nMachines
            if i < n + 1
                e[i, j] = max(e[i, j-1], e[i-1, j]) + inputs.times[solution.jobs[i], j]
            end
            if i > 1
                q[n+2-i, inputs.nMachines+1-j] =
                    max(q[n+2-i, inputs.nMachines+2-j], q[n+3-i, inputs.nMachines+1-j]) +
                    inputs.times[solution.jobs[n+2-i], inputs.nMachines+1-j]
            end
            f[i, j] = max(f[i, j-1], e[i-1, j]) + inputs.times[kJob, j]
        end
    end
    # Find position of minimum makespan
    Mi = maximum(f.data + q.data, dims = 2)[1:end]
    index = argmin(Mi[1:min(k, end)])
    # Insert job in the sequence and update makespan
    insert!(solution.jobs, index, kJob)
    solution.makespan = Mi[index]
end

function PFSP_Heuristic(inputs, jobIndices)
    solution = Solution()
    push!(solution.jobs, jobIndices[1])
    for i = 2:length(jobIndices)
        insertJobIntoSequence(solution, inputs, i, jobIndices[i])
    end
    return solution
end

function createBiasedJobsSequence(jobs, rng)
    jobsCopy = copy(jobs)
    biasedJobs = Int[]
    for _ = 1:length(jobsCopy)
        index = trunc(Int, length(jobsCopy) * (1 - sqrt(1 - rand(rng)))) + 1
        push!(biasedJobs, jobsCopy[index])
        deleteat!(jobsCopy, index)
    end
    return biasedJobs
end

function PFSP_Multistart(inputs, rng)
    totalTimes = sum(inputs.times, dims = 2)
    sortedJobIndices = sortperm(vec(totalTimes), rev = true)
    nehSolution = @time PFSP_Heuristic(inputs, sortedJobIndices)
    println("NEH makespan: $(nehSolution.makespan)")
    baseSolution = nehSolution
    nIter = 0
    while baseSolution.makespan >= nehSolution.makespan && nIter < inputs.nJobs
        nIter += 1
        biasedJobs = createBiasedJobsSequence(sortedJobIndices, rng)
        newSolution = PFSP_Heuristic(inputs, biasedJobs)
        if newSolution.makespan < baseSolution.makespan
            baseSolution = newSolution
        end
    end
    return baseSolution
end

function localSearch(solution, inputs, rng)
    improve = true
    while improve
        improve = false
        for index in randperm(rng, length(solution.jobs))
            job = solution.jobs[index]
            newSolution = Solution(solution.jobs[:], solution.makespan, 0)
            deleteat!(newSolution.jobs, index)
            insertJobIntoSequence(newSolution, inputs, index, job)
            if newSolution.makespan < solution.makespan
                solution = newSolution
                improve = true
            end
        end
    end
    return solution
end

function perturbation(baseSolution, inputs, rng)
    solution = Solution()
    solution.jobs = copy(baseSolution.jobs)
    solution.makespan = baseSolution.makespan
    # Select two random jobs from the sequence
    aIndex, bIndex = rand(rng, 1:length(solution.jobs), 2)
    # Swap the jobs at the two random positions
    solution.jobs[aIndex], solution.jobs[bIndex] =
        solution.jobs[bIndex], solution.jobs[aIndex]
    if bIndex < aIndex
        aIndex, bIndex = bIndex, aIndex
    end
    # Insert the left-most swapped job where the makespan is minimized
    aJob = splice!(solution.jobs, aIndex)
    insertJobIntoSequence(solution, inputs, aIndex, aJob)
    # Insert the right-most swapped job where the makespan is minimized
    bJob = splice!(solution.jobs, bIndex)
    insertJobIntoSequence(solution, inputs, bIndex, bJob)
    return solution
end

function detExecution(inputs, test, rng)
    # Create a base solution using a randomized NEH approach
    baseSolution = @time PFSP_Multistart(inputs, rng)
    println("Multistart makespan: $(baseSolution.makespan)")
    baseSolution = @time localSearch(baseSolution, inputs, rng)
    bestSolution = baseSolution
    println("Multistart makespan: $(bestSolution.makespan)")

    # Start the iterated local search process
    credit = 0
    elapsedTime = 0
    startTime = time()
    maxTime = inputs.nJobs * inputs.nMachines * t
    while elapsedTime < maxTime
        # Perturb the base solution to find a new solution
        solution = perturbation(baseSolution, inputs, rng)
        solution = localSearch(solution, inputs, rng)
        # Check if the solution is adept to be the new base solution
        delta = solution.makespan - baseSolution.makespan
        if delta < 0
            credit = -delta
            baseSolution = solution
            if solution.makespan < bestSolution.makespan
                bestSolution = solution
                bestSolution.time = time() - startTime
            end
        elseif 0 < delta <= credit
            credit = 0
            baseSolution = solution
        end
        # Update the elapsed time before evaluating the stopping criterion
        elapsedTime = time() - startTime
    end
    return bestSolution
end

function printSolution(solution)
    # println("Jobs: " * join([string(job) for job in solution.jobs], ", "))
    println("Makespan: $(round(solution.makespan, digits=2))")
    println("Time: $(round(solution.time, digits=2))")
end


function main()
    base_path = "/Users/mtabares/dev/icso-neh/"

    # Read tests from the file
    tests = readTests(joinpath(base_path, "tests", "test2run.txt"))

    for test in tests
        # Read inputs for the test inputs
        inputs = readInputs(joinpath(base_path, "inputs"), test.instanceName)
        rng = MersenneTwister(test.seed)

        # Compute the best deterministic solution
        solution = detExecution(inputs, test, rng)
        println("OBD $(inputs.name)")
        printSolution(solution)
    end
end

main()