"""
    SimpleIron(; excess_scavenging_enhancement = 1000)

Parameterisation for iron evolution, not the "complex chemistry" model
of Aumount et al, 2015. Iron is scavenged (i.e. perminemtly removed from
the model) when the free iron concentration exeeds the ligand concentration
at a rate modified by `excess_scavenging_enhancement`.
"""
@kwdef struct SimpleIron{FT}
    excess_scavenging_enhancement :: FT = 1000 # unitless
     maximum_ligand_concentration :: FT = 0.6  # μmol Fe / m³
           dissolved_ligand_ratio :: FT = 0.09 # μmol Fe / mmol C
end

const SimpleIronPISCES = PISCES{<:Any, <:Any, <:Any, <:Any, <:Any, SimpleIron}

@inline function (bgc::SimpleIronPISCES)(i, j, k, grid, val_name::Val{:Fe}, clock, fields)
    λ̄ = iron.excess_scavenging_enhancement

    λFe = iron_scavenging_rate(bgc.particulate_organic_matter, i, j, k, grid, bgc, clock, fields)
    
    Fe′ = free_iron(bgc.iron, i, j, k, grid, bgc, clock, fields)

    total_ligand_concentration = ligand_concentration(bgc.iron, i, j, k, grid, bgc, clock, fields)

    # terminal process which removes iron from the ocean
    ligand_aggregation = λ̄ * λFe * max(0, Fe - total_ligand_concentration) * Fe′

    colloidal_aggregation, = aggregation_of_colloidal_iron(bgc.dissolved_organic_matter, i, j, k, grid, bgc, clock, fields)

    # scavenging and bacterial uptake
    scavenging = iron_scavenging(bgc.particulate_organic_matter, i, j, k, grid, bgc, clock, fields)

    BactFe = bacterial_iron_uptake(bgc.particulate_organic_matter, i, j, k, grid, bgc, clock, fields)

    # particle breakdown
    small_particles = degredation(bgc.particulate_organic_matter, Val(:SFe), i, j, k, grid, bgc, clock, fields)

    # consumption
    consumption = uptake(bgc.phytoplankton, val_name, i, j, k, grid, bgc, clock, fields)

    # waste
    grazing_waste = non_assimilated_iron(bgc.zooplankton, i, j, k, grid, bgc, clock, fields)

    upper_trophic_waste = upper_trophic_iron_waste(bgc.zooplankton, i, j, k, grid, bgc, clock, fields)

    return (small_particles + grazing_waste + upper_trophic_waste
            - consumption - ligand_aggregation - colloidal_aggregation - scavenging - BactFe)
end

@inline function ligand_concentration(iron::SimpleIron, i, j, k, grid, bgc, clock, fields)
    Lₜᵐᵃˣ = iron.maximum_ligand_concentration

    DOC = @inbounds fields.DOC[i, j, k]

    Lₜ = iron.dissolved_ligand_ratio * DOC - Lₜᵐᵃˣ
    
    return max(Lₜᵐᵃˣ, Lₜ)
end