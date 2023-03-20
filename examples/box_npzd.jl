# # Box model
# In this example we will setup a simple NPZD biogeochemical model in a single box configuration. This demonstrates:
# - How to setup OceanBioME's biogeochemical models as a stand-alone box model

# ## Install dependencies
# First we will check we have the dependencies installed
# ```julia
# using Pkg
# pkg"add OceanBioME, CairoMakie, DiffEqBase, OrdinaryDiffEq"
# ```

# ## Model setup
# Load the packages and setup the initial and forcing conditions
using OceanBioME

minute = minutes = 60
hour = hour = 60 * minutes
day = days = hours * 24  # define the length of a day in seconds
year = years = day * 365  # define the length of a year in days

# This is forced by a prescribed time-dependent photosynthetically available radiation (PAR)
PAR⁰(t) = 50 * (1 - cos((t + 15days) * 2π / (365days))) * (1 / (1 + 0.2 * exp(-((mod(t, 365days)-200days)/50days)^2))) .+ 10

z = 10# specify the nominal depth of the box for the PAR profile
PAR(t) = PAR⁰(t) * exp(- z * 0.1) # Modify the PAR based on the nominal depth and exponential decay 

T(t) = 5 * (1 - cos((t + 30days)*2π/(365days)))/2 + 15

# Set up the model. Here, first specify the biogeochemical model, followed by initial conditions and the start and end times
model = BoxModel(biogeochemistry = NutrientPhytoplanktonZooplanktonDetritus(grid = BoxModelGrid()), forcing = (; PAR, T))
model.Δt = 2day
model.stop_time = 10years

set!(model, N = 7.0, P = 0.01, Z = 0.05)

# ## Run the model (should only take a few seconds)
@info "Running the model..."
run!(model, save_interval = 1, save = SaveBoxModel("box_npzd.jld2"))

@info "Plotting the results..."
# ## Plot the results
using JLD2, CairoMakie
vars = (:N, :P, :Z, :D, :T, :PAR)
file = jldopen("box_npzd.jld2")
times = keys(file["values"])
timeseries = NamedTuple{vars}(ntuple(t -> zeros(length(times)), length(vars)))

for (idx, time) in enumerate(times)
    values = file["values/$time"]
    for tracer in vars
        getproperty(timeseries, tracer)[idx] = values[tracer]
    end
end

close(file)

fig = Figure(resolution = (1600, 1000))

plt_times = parse.(Float64, times)./day

axs = []

for (idx, tracer) in enumerate(vars)
    push!(axs, Axis(fig[floor(Int, (idx - 1)/3) + 1, (idx - 1) % 3 + 1], ylabel="$tracer", xlabel="Day"))
    lines!(axs[end], plt_times, timeseries[tracer])
end
save("box_npzd.png", fig)

# ![Results](box.png)
