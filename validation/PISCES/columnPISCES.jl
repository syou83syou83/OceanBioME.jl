# # [One-dimensional column example](@id OneD_column)
# In this example we setup a simple 1D column with the [LOBSTER](@ref LOBSTER) biogeochemical model and observe its evolution. The example demonstrates:
# - How to setup OceanBioME's biogeochemical models
# - How to visualise results
# This is forced by idealised mixing layer depth and surface photosynthetically available radiation (PAR) which are setup first.

# ## Install dependencies
# First we check we have the dependencies installed
# ```julia
# using Pkg
# pkg"add OceanBioME, Oceananigans, CairoMakie"
# ```

# ## Model setup
# We load the packages and choose the default LOBSTER parameter set
using OceanBioME, Oceananigans, Printf
using Oceananigans.Fields: FunctionField, ConstantField
using Oceananigans.Units

const year = years = 365days
nothing #hide

# ## Surface PAR and turbulent vertical diffusivity based on idealised mixed layer depth 
# Setting up idealised functions for PAR and diffusivity (details here can be ignored but these are typical of the North Atlantic), temperaeture and euphotic layer

@inline PAR⁰(x,y,t) = 60 * (1 - cos((t + 15days) * 2π / year)) * (1 / (1 + 0.2 * exp(-((mod(t, year) - 200days) / 50days)^2))) + 2

@inline H(t, t₀, t₁) = ifelse(t₀ < t < t₁, 1.0, 0.0)

@inline fmld1(t) = H(t, 50days, year) * (1 / (1 + exp(-(t - 100days) / 5days))) * (1 / (1 + exp((t - 330days) / 25days)))

@inline MLD(x, y, z, t) = - (10 + 340 * (1 - fmld1(year - eps(year)) * exp(-mod(t, year) / 25days) - fmld1(mod(t, year))))

@inline κₜ(x, y, z, t) = (1e-2 * (1 + tanh((z - MLD(x, y, z, t)) / 10)) / 2 + 1e-4)

@inline temp(x, y, z, t) = (2.4 * cos(t * 2π / year + 50days) + 10)*exp(z/10)

@inline euphotic(x, y, z, t) = - 50.0
nothing #hide

#The commented equation is the correct form of w_GOC, but have not figured out how to implement this
#w_GOC(z) = 30/day + (200/day - 30/day)*(max(0, abs(z)-abs(zₘₓₗ)))/(5000)
PAR_func(x, y, z, t) = PAR⁰(t)*exp(z/10) # Modify the PAR based on the nominal depth and exponential decay

PAR_func1(x, y, z, t) = 1/3*PAR⁰(t)*exp(z/10)
PAR_func2(x, y, z, t) = 1/3*PAR⁰(t)*exp(z/10)
PAR_func3(x, y, z, t) = 1/3*PAR⁰(t)*exp(z/10)

mixed_layer_depth = ConstantField(-100)
euphotic_layer_depth = ConstantField(-50)
yearly_maximum_silicate = ConstantField(1) 
dust_deposition = ConstantField(0)
carbonate_sat_ratio = ConstantField(0)

#w_GOC(z) = 30/day + (200/day - 30/day)*(max(0, abs(z)-100))/(5000)

w_GOC = 30/day
w_POC = 2.0/day
grid = RectilinearGrid(size = (1, 1, 100), extent = (20meters, 20meters, 400meters))

clock = Clock(; time = 0.0)

zₘₓₗ = FunctionField{Center, Center, Center}(MLD, grid; clock)
zₑᵤ = FunctionField{Center, Center, Center}(euphotic, grid; clock)

#ff = FunctionField{Nothing, Nothing, Face}(w_GOC, grid)

# ## Model
# First we define the biogeochemical model including carbonate chemistry (for which we also define temperature (``T``) and salinity (``S``) fields)
# and scaling of negative tracers(see discussion in the [positivity preservation](@ref pos-preservation))
# and then setup the Oceananigans model with the boundary condition for the DIC based on the air-sea CO₂ flux.

biogeochemistry = PISCES(; grid,
                           light_attenuation_model = MultiBandPhotosyntheticallyActiveRadiation(; grid, surface_PAR = PAR⁰), 
                           sinking_speeds = (; POC = w_POC, SFe = w_POC, GOC = w_GOC, BFe = w_GOC, PSi = w_GOC, CaCO₃ = w_GOC),
                           mixed_layer_depth = zₘₓₗ, euphotic_layer_depth = zₑᵤ)

CO₂_flux = CarbonDioxideGasExchangeBoundaryCondition()

funT = FunctionField{Center, Center, Center}(temp, grid; clock)
S = ConstantField(35)

@info "Setting up the model..."
model = NonhydrostaticModel(; grid,
                              clock,
                              closure = ScalarDiffusivity(VerticallyImplicitTimeDiscretization(), κ = κₜ),
                              biogeochemistry,
                              boundary_conditions = (DIC = FieldBoundaryConditions(top = CO₂_flux), ),
                              auxiliary_fields = (; S)
                              )
                              

@info "Setting initial values..."
set!(model, P = 6.95, D = 6.95, Z = 0.695,  M = 0.695, Pᶜʰˡ = 1.671,  Dᶜʰˡ = 1.671, Pᶠᵉ =7e-6 * 1e9 / 1e6 * 6.95, Dᶠᵉ = 7e-6 * 1e9 / 1e6 * 6.95, Dˢⁱ = 1.162767, DOC = 0.0, POC = 0.0, GOC = 0.0, SFe = 7e-6 * 1e9 / 1e6 *1.256, BFe =7e-6 * 1e9 / 1e6 *1.256, NO₃ = 6.202, NH₄ = 0.25*6.202, PO₄ = 0.8722, Fe = 1.256, Si = 7.313, CaCO₃ = 0.001, DIC = 2139.0, Alk = 2366.0, O₂ = 237.0, T = funT) #Using Copernicus Data (26.665, 14.), Calcite is not correct, but this is to see it on the graphs
# ## Simulation
# Next we setup a simulation and add some callbacks that:
# - Show the progress of the simulation
# - Store the model and particles output

simulation = Simulation(model, Δt = 50minutes, stop_time = 2years)

progress_message(sim) = @printf("Iteration: %04d, time: %s, Δt: %s, wall time: %s\n",
                                iteration(sim),
                                prettytime(sim),
                                prettytime(sim.Δt),
                                prettytime(sim.run_wall_time))
                                                                  
simulation.callbacks[:progress] = Callback(progress_message, TimeInterval(10day)
)

#NaN Checker function. Could be removed to improve speed, if confident of model stability
function non_zero_fields!(model) 
    @inbounds for (idx, tracer) in enumerate(model.tracers)
        for i in 1:50
            if isnan(tracer[1,1,i])
                throw("$(keys(model.tracers)[idx]) has gone NaN")
            else
                tracer[1, 1, i] = max(0, tracer[1, 1, i])
            end
        end
        
    end
    return nothing
end
simulation.callbacks[:non_zero_fields] = Callback(non_zero_fields!, callsite = UpdateStateCallsite())
filename = "column"
simulation.output_writers[:profiles] = JLD2OutputWriter(model, model.tracers,
                                                        filename = "$filename.jld2",
                                                        schedule = TimeInterval(1day),
                                                        overwrite_existing = true)
nothing #hide

# ## Run!
# We are ready to run the simulation
run!(simulation)



# ## Load saved output
# Now we can load the results and do some post processing to diagnose the air-sea CO₂ flux. Hopefully, this looks different to the example without kelp!

    P = FieldTimeSeries("$filename.jld2", "P")
    D = FieldTimeSeries("$filename.jld2", "D")
    Z = FieldTimeSeries("$filename.jld2", "Z")
    M = FieldTimeSeries("$filename.jld2", "M")
 Pᶜʰˡ = FieldTimeSeries("$filename.jld2", "Pᶜʰˡ")
 Dᶜʰˡ = FieldTimeSeries("$filename.jld2", "Dᶜʰˡ")
  Pᶠᵉ = FieldTimeSeries("$filename.jld2", "Pᶠᵉ")
  Dᶠᵉ = FieldTimeSeries("$filename.jld2", "Dᶠᵉ")
  Dˢⁱ = FieldTimeSeries("$filename.jld2", "Dˢⁱ")
  DOC = FieldTimeSeries("$filename.jld2", "DOC")
  POC = FieldTimeSeries("$filename.jld2", "POC")
  GOC = FieldTimeSeries("$filename.jld2", "GOC")
  SFe = FieldTimeSeries("$filename.jld2", "SFe")
  BFe = FieldTimeSeries("$filename.jld2", "BFe")
  PSi = FieldTimeSeries("$filename.jld2", "PSi")
  NO₃ = FieldTimeSeries("$filename.jld2", "NO₃")
  NH₄ = FieldTimeSeries("$filename.jld2", "NH₄")
  PO₄ = FieldTimeSeries("$filename.jld2", "PO₄")
   Fe = FieldTimeSeries("$filename.jld2", "Fe")
   Si = FieldTimeSeries("$filename.jld2", "Si")
CaCO₃ = FieldTimeSeries("$filename.jld2", "CaCO₃")
  DIC = FieldTimeSeries("$filename.jld2", "DIC")
  Alk = FieldTimeSeries("$filename.jld2", "Alk")
   O₂ = FieldTimeSeries("$filename.jld2", "O₂")
                 

x, y, z = nodes(P)
times = P.times
nothing #hide

# We compute the  air-sea CO₂ flux at the surface (corresponding to vertical index `k = grid.Nz`) and
# the carbon export by computing how much carbon sinks below some arbirtrary depth; here we use depth 
# that corresponds to `k = grid.Nz - 20`.
air_sea_CO₂_flux = zeros(length(times))
carbon_export = zeros(length(times))

using Oceananigans.Biogeochemistry: biogeochemical_drift_velocity

for (i, t) in enumerate(times)
    #air_sea_CO₂_flux[i] = CO₂_flux.condition.func(0.0, 0.0, t, DIC[1, 1, grid.Nz, i], Alk[1, 1, grid.Nz, i], temp(1, 1, 0, t), 35)
    carbon_export[i] = (POC[1, 1, grid.Nz-20, i] * biogeochemical_drift_velocity(model.biogeochemistry, Val(:POC)).w[1, 1, grid.Nz-20] +
                        GOC[1, 1, grid.Nz-20, i] * biogeochemical_drift_velocity(model.biogeochemistry, Val(:GOC)).w[1, 1, grid.Nz-20]) * redfield(Val(:GOC), model.biogeochemistry)
end

# Both `air_sea_CO₂_flux` and `carbon_export` are in units `mmol CO₂ / (m² s)`.

# ## Plot
# Finally, we plot!

using CairoMakie

fig = Figure(size = (4000, 2100), fontsize = 20)

axis_kwargs = (xlabel = "Time (days)", ylabel = "z (m)", limits = ((0, times[end] / days), (-400meters, 0)))

axP = Axis(fig[1, 1]; title = "Nanophytoplankton concentration (μmolC/L)", axis_kwargs...)
hmP = heatmap!(times / days, z, interior(P, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[1, 2], hmP)

axD = Axis(fig[1,3]; title = "Diatom concentration (μmolC/L)", axis_kwargs...)
hmD = heatmap!(times / days, z, interior(D, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[1, 4], hmD)

axZ = Axis(fig[1, 5]; title = "Microzooplankton concentration (μmolC/L)", axis_kwargs...)
hmZ = heatmap!(times / days, z, interior(Z, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[1, 6], hmZ)

axM = Axis(fig[1,7]; title = "Mesozooplankton concentration (μmolC/L)", axis_kwargs...)
hmM = heatmap!(times / days, z, interior(M, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[1, 8], hmM)

axPᶜʰˡ  = Axis(fig[2,1]; title = "Chlorophyll concentration in P (μgChl/L)", axis_kwargs...)
hmPᶜʰˡ  = heatmap!(times / days, z, interior(Pᶜʰˡ, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[2, 2], hmPᶜʰˡ)

axDᶜʰˡ = Axis(fig[2,3]; title = "Chlorophyll concentration in D (μgChl/L)", axis_kwargs...)
hmDᶜʰˡ = heatmap!(times / days, z, interior(Dᶜʰˡ, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[2, 4], hmDᶜʰˡ)

axPᶠᵉ = Axis(fig[2,5]; title = "Iron concentration in P (nmolFe/L)", axis_kwargs...)
hmPᶠᵉ = heatmap!(times / days, z, interior(Pᶠᵉ, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[2,6], hmPᶠᵉ)

axDᶠᵉ = Axis(fig[2,7]; title = "Iron concentration in D (nmolFe/L)", axis_kwargs...)
hmDᶠᵉ = heatmap!(times / days, z, interior(Dᶠᵉ, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[2, 8], hmDᶠᵉ)

axDˢⁱ  = Axis(fig[3,1]; title = "Silicon concentration in D (μmolSi/L)", axis_kwargs...)
hmDˢⁱ  = heatmap!(times / days, z, interior(Dˢⁱ, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[3, 2], hmDˢⁱ)

axDOC = Axis(fig[3,3]; title = "Dissolved Organic Carbon (μmolC/L)", axis_kwargs...)
hmDOC = heatmap!(times / days, z, interior(DOC, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[3, 4], hmDOC)

axPOC = Axis(fig[3,5]; title = "Small particles of Organic Carbon (μmolC/L)", axis_kwargs...)
hmPOC = heatmap!(times / days, z, interior(POC, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[3,6], hmPOC)

axGOC = Axis(fig[3,7]; title = "Large particles of Organic Carbon (μmolC/L)", axis_kwargs...)
hmGOC = heatmap!(times / days, z, interior(GOC, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[3, 8], hmGOC)

axSFe  = Axis(fig[4,1]; title = "Iron in small particles (nmolFe/L)", axis_kwargs...)
hmSFe  = heatmap!(times / days, z, interior(SFe, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[4, 2], hmSFe)

axBFe = Axis(fig[4,3]; title = "Iron in large particles (nmolFe/L)", axis_kwargs...)
hmBFe = heatmap!(times / days, z, interior(BFe, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[4, 4], hmBFe)

axPSi = Axis(fig[4,5]; title = "Silicon in large particles (μmolSi/L)", axis_kwargs...)
hmPSi = heatmap!(times / days, z, interior(PSi, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[4,6], hmPSi)

axNO₃ = Axis(fig[4, 7]; title = "Nitrate concentration (μmolN/L)", axis_kwargs...)
hmNO₃ = heatmap!(times / days, z, interior(NO₃, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[4, 8], hmNO₃)

axNH₄  = Axis(fig[5,1]; title = "Ammonium concentration (μmolN/L)", axis_kwargs...)
hmNH₄  = heatmap!(times / days, z, interior(NH₄, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[5, 2], hmNH₄)

axPO₄ = Axis(fig[5,3]; title = "Phosphate concentration (μmolP/L)", axis_kwargs...)
hmPO₄ = heatmap!(times / days, z, interior(PO₄, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[5, 4], hmPO₄)

axFe = Axis(fig[5,5]; title = "Dissolved Iron Concentration (nmolFe/L)", axis_kwargs...)
hmFe = heatmap!(times / days, z, interior(Fe, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[5,6], hmFe)

axSi = Axis(fig[5, 7]; title = "Silicon concentration (μmolSi/L)", axis_kwargs...)
hmSi = heatmap!(times / days, z, interior(Si, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[5, 8], hmSi)

axCaCO₃  = Axis(fig[6,1]; title = "Calcite concentration (μmolC/L)", axis_kwargs...)
hmCaCO₃  = heatmap!(times / days, z, interior(CaCO₃, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[6, 2], hmCaCO₃)

axO₂ = Axis(fig[6,3]; title = "Oxygen concentration (μmolO₂/L)", axis_kwargs...)
hmO₂ = heatmap!(times / days, z, interior(O₂, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[6, 4], hmO₂)

axDIC = Axis(fig[6,5]; title = "Dissolved Inorganic Carbon concentration (μmolC/L)", axis_kwargs...)
hmDIC = heatmap!(times / days, z, interior(DIC, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[6,6], hmDIC)

axAlk = Axis(fig[6, 7]; title = "Total Alkalinity (μmolN/L)", axis_kwargs...)
hmAlk = heatmap!(times / days, z, interior(Alk, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[6, 8], hmAlk)

CO₂_molar_mass = (12 + 2 * 16) * 1e-3 # kg / mol

axfDIC = Axis(fig[7, 1], xlabel = "Time (days)", ylabel = "Flux (kgCO₂/m²/year)",
                         title = "Air-sea CO₂ flux and Sinking", limits = ((0, times[end] / days), nothing))
lines!(axfDIC, times / days, air_sea_CO₂_flux / 1e3 * CO₂_molar_mass * year, linewidth = 3, label = "Air-sea flux")
lines!(axfDIC, times / days, carbon_export / 1e3    * CO₂_molar_mass * year, linewidth = 3, label = "Sinking export")
Legend(fig[7, 2], axfDIC, framevisible = false)

#Plotting a graph of Mixed Layer Depth
axs = []
push!(axs, Axis(fig[7,3], xlabel = "Time (days)", title = "Mixed Layer Depth (m)"))
lines!(axs[end], (0:1day:2years)/days, x ->  MLD(0, 0, 0, x*days), linewidth = 3)
fig
