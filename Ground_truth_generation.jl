cd(dirname(@__FILE__))
include("rr_funcs-Jin.jl")
using Random
using Distributions # generate normal distribution for noise
using StatsBase # random pick reaction by weight
disableLoggingToConsole() # try to disable some warnings like NLEQ

perturbation_percentage = 0.1
global nSpecies = 15 # this number excludes the input and output species but includes nSpecies_gene
#Therefore, the total number of species should be (nSpecies+2)
global nRxns_limitation = 15
global nSpecies_gene = 2
# (nSpecies-nSpecies_gene) >= 4 for the case of BIBI
# nSpecies >= 5 for the case of double catalyzation
# nSpecies >= 13: 6 to initiate input and output reactions + next input and output layer 7
# random values assignment
global species = ["S$i" for i = 1:nSpecies]
global gene_species = species[1:nSpecies_gene]

rnd_species = 10. # random number [0,10)
rnd_parameter = 1. # random number [0,1)
noise = false
abs_noise = 0.005
#low noise
rel_noise = 0.05
#high noise
#rel_noise=0.2
#only consider the networks with at least one boundary species and one floating species
#minimum number: 5 species, and 4 reactions for the bi-stable states
perturbation_flag = false
concentration_perturb = 2.

setConfigBool("ROADRUNNER_DISABLE_WARNINGS", 1)
function rv_specs(ids_species, ids_rv)
    for i = 1:size(ids_rv)[1]
        if ids_rv[i] in ids_species
            filter!(e->e≠ids_rv[i], ids_species)
        end
    end
    return ids_species
end

function steadyState_self(rr::Ptr{Nothing})
    value = 0
    simulate_str = simulate(rr)
    try
        nSpecies_floating = getNumberOfFloatingSpecies(rr)
        for j = 1:nSpecies_floating
            temp = getRateOfChange(rr, (j-1))
            value += temp*temp
        end
        value = sqrt(value)
        if value >= 1e-6 || isnan(value) || isinf(value)
            e = ErrorException("self_func: no steady state")
            throw(e)
        end
    finally
        freeRRCData(simulate_str)
    end
    return value
end

function speciesPerturbationMatrix(rr, nSpecies_gene, perturbation_percentage)
    global S_change_scaled
    S_change_scaled = zeros(nSpecies_gene, nSpecies)
    S_list = getFloatingSpeciesIds(rr)
    nSpecies_floating = getNumberOfFloatingSpecies(rr)
    B_list = getBoundarySpeciesIds(rr)
    nSpecies_boundary = getNumberOfBoundarySpecies(rr)
    setConfigInt("LOADSBMLOPTIONS_CONSERVED_MOIETIES", 1)
    try
        steadyState(rr)
        #steadyState_self(rr)
        S_before = zeros(0)
        gene_S_before = zeros(0)
        gene_S_perturb = zeros(0)
        C_S = getFloatingSpeciesConcentrations(rr)
        C_B = getBoundarySpeciesConcentrations(rr)
        for i = 1:nSpecies
            for j = 1:nSpecies_floating
                if occursin("S$i", getStringElement(S_list, j-1))
                    temp_id = j-1
                    append!(S_before, getVectorElement(C_S, temp_id))
                end
            end
        end
        for i = 1:nSpecies
            for j = 1:nSpecies_boundary
                if occursin("S$i", getStringElement(B_list, j-1))
                    temp_id = j-1
                    append!(S_before, getVectorElement(C_B, temp_id))
                end
            end
        end
        for i = 1:nSpecies_gene
            for j = 1:nSpecies_floating
                if occursin(gene_species[i], getStringElement(S_list, j-1))
                    temp_id = j-1
                    append!(gene_S_before, getVectorElement(C_S, temp_id))
                end
            end
        end
        for i = 1:nSpecies_gene
            for j = 1:nSpecies_boundary
                if occursin(gene_species[i], getStringElement(B_list, j-1))
                    temp_id = j-1
                    append!(gene_S_before, getVectorElement(C_B, temp_id))
                end
            end
        end
        freeVector(C_S)
        freeVector(C_B)
        for i = 1:nSpecies_gene
            append!(gene_S_perturb, gene_S_before[i]*perturbation_percentage)
        end
        S_after_up = zeros(nSpecies_gene, nSpecies)
        S_after_down = zeros(nSpecies_gene, nSpecies)
        S_change = zeros(nSpecies_gene, nSpecies)
        for i = 1:nSpecies_gene
            for j = 1:nSpecies
                resetRR(rr)
                steadyState(rr)
                #steadyState_self(rr)
                for m = 1:nSpecies_floating
                    if occursin(gene_species[i], getStringElement(S_list, m-1))
                        temp_id = m-1
                        C_S = getFloatingSpeciesConcentrations(rr)
                        temp = getVectorElement(C_S, temp_id) + gene_S_perturb[i]*0.5
                        freeVector(C_S)
                        setFloatingSpeciesByIndex(rr, temp_id, temp)
                        steadyState(rr)
                        #steadyState_self(rr)
                        for n = 1: nSpecies_floating
                            if occursin("S$j", getStringElement(S_list, n-1))
                                temp_id_2 = n-1
                                C_S = getFloatingSpeciesConcentrations(rr)
                                S_after_up[i,j] = getVectorElement(C_S, temp_id_2)
                                freeVector(C_S)
                            end
                        end
                        for n = 1: nSpecies_boundary
                            if occursin("S$j", getStringElement(B_list, n-1))
                                temp_id_2 = n-1
                                C_B = getBoundarySpeciesConcentrations(rr)
                                S_after_up[i,j] = getVectorElement(C_B, temp_id_2)
                                freeVector(C_B)
                            end
                        end
                    end
                end
                for m = 1:nSpecies_boundary
                    if occursin(gene_species[i], getStringElement(B_list, m-1))
                        temp_id = m-1
                        C_B = getBoundarySpeciesConcentrations(rr)
                        temp = getVectorElement(C_B, temp_id) + gene_S_perturb[i]*0.5
                        freeVector(C_B)
                        setBoundarySpeciesByIndex(rr, temp_id, temp)
                        steadyState(rr)
                        #steadyState_self(rr)
                        for n = 1: nSpecies_floating
                            if occursin("S$j", getStringElement(S_list, n-1))
                                temp_id_2 = n-1
                                C_S = getFloatingSpeciesConcentrations(rr)
                                S_after_up[i,j] = getVectorElement(C_S, temp_id_2)
                                freeVector(C_S)
                            end
                        end
                        for n = 1: nSpecies_boundary
                            if occursin("S$j", getStringElement(B_list, n-1))
                                temp_id_2 = n-1
                                C_B = getBoundarySpeciesConcentrations(rr)
                                S_after_up[i,j] = getVectorElement(C_B, temp_id_2)
                                freeVector(C_B)
                            end
                        end
                        C_B = getBoundarySpeciesConcentrations(rr)
                        temp = getVectorElement(C_B, temp_id) - gene_S_perturb[i]*0.5
                        freeVector(C_B)
                        setBoundarySpeciesByIndex(rr, temp_id, temp)
                    end
                end
            end
        end
        for i = 1:nSpecies_gene
            for j = 1:nSpecies
                resetRR(rr)
                steadyState(rr)
                #steadyState_self(rr)
                for m = 1:nSpecies_floating
                    if occursin(gene_species[i], getStringElement(S_list, m-1))
                        temp_id = m-1
                        C_S = getFloatingSpeciesConcentrations(rr)
                        temp = getVectorElement(C_S, temp_id) - gene_S_perturb[i]*0.5
                        freeVector(C_S)
                        setFloatingSpeciesByIndex(rr, temp_id, temp)
                        steadyState(rr)
                        #steadyState_self(rr)
                        for n = 1: nSpecies_floating
                            if occursin("S$j", getStringElement(S_list, n-1))
                                temp_id_2 = n-1
                                C_S = getFloatingSpeciesConcentrations(rr)
                                S_after_down[i,j] = getVectorElement(C_S, temp_id_2)
                                freeVector(C_S)
                            end
                        end
                        for n = 1: nSpecies_boundary
                            if occursin("S$j", getStringElement(B_list, n-1))
                                temp_id_2 = n-1
                                C_B = getBoundarySpeciesConcentrations(rr)
                                S_after_down[i,j] = getVectorElement(C_B, temp_id_2)
                                freeVector(C_B)
                            end
                        end
                    end
                end
                for m = 1:nSpecies_boundary
                    if occursin(gene_species[i], getStringElement(B_list, m-1))
                        temp_id = m-1
                        C_B = getBoundarySpeciesConcentrations(rr)
                        temp = getVectorElement(C_B, temp_id) - gene_S_perturb[i]*0.5
                        freeVector(C_B)
                        setBoundarySpeciesByIndex(rr, temp_id, temp)
                        steadyState(rr)
                        #steadyState_self(rr)
                        for n = 1: nSpecies_floating
                            if occursin("S$j", getStringElement(S_list, n-1))
                                temp_id_2 = n-1
                                C_S = getFloatingSpeciesConcentrations(rr)
                                S_after_down[i,j] = getVectorElement(C_S, temp_id_2)
                                freeVector(C_S)
                            end
                        end
                        for n = 1: nSpecies_boundary
                            if occursin("S$j", getStringElement(B_list, n-1))
                                temp_id_2 = n-1
                                C_B = getBoundarySpeciesConcentrations(rr)
                                S_after_down[i,j] = getVectorElement(C_B, temp_id_2)
                                freeVector(C_B)
                            end
                        end
                        C_B = getBoundarySpeciesConcentrations(rr)
                        temp = getVectorElement(C_B, temp_id) + gene_S_perturb[i]*0.5
                        freeVector(C_B)
                        setBoundarySpeciesByIndex(rr, temp_id, temp)
                    end
                end
            end
        end
        for i = 1:nSpecies_gene
            for j = 1:nSpecies
                S_change[i,j] = S_after_up[i,j] - S_after_down[i,j]
                if S_before[j] != 0.
                    S_change_scaled[i,j] = S_change[i,j]*S_before[i]/S_before[j]
                else
                    S_change_scaled[i,j] = NaN # here needs to change to n/a
                end
            end
        end
        freeStringArray(S_list)
        freeStringArray(B_list)
    catch e
        for i = 1: nSpecies_gene
            for j = 1: nSpecies
                S_change_scaled[i,j] = NaN
            end
        end
    end
    return S_change_scaled
end

function speciesPerturbationMatrix_up_only(rr, nSpecies_gene, perturbation_percentage)
    global S_change_scaled
    S_change_scaled = zeros(nSpecies_gene, nSpecies)
    S_list = getFloatingSpeciesIds(rr)
    nSpecies_floating = getNumberOfFloatingSpecies(rr)
    B_list = getBoundarySpeciesIds(rr)
    nSpecies_boundary = getNumberOfBoundarySpecies(rr)
    setConfigInt("LOADSBMLOPTIONS_CONSERVED_MOIETIES", 1)
    try
        steadyState(rr)
        #steadyState_self(rr)
        S_before = zeros(0)
        gene_S_before = zeros(0)
        gene_S_perturb = zeros(0)
        C_S = getFloatingSpeciesConcentrations(rr)
        C_B = getBoundarySpeciesConcentrations(rr)
        for i = 1:nSpecies
            for j = 1:nSpecies_floating
                if occursin("S$i", getStringElement(S_list, j-1))
                    temp_id = j-1
                    append!(S_before, getVectorElement(C_S, temp_id))
                end
            end
        end
        for i = 1:nSpecies
            for j = 1:nSpecies_boundary
                if occursin("S$i", getStringElement(B_list, j-1))
                    temp_id = j-1
                    append!(S_before, getVectorElement(C_B, temp_id))
                end
            end
        end
        for i = 1:nSpecies_gene
            for j = 1:nSpecies_floating
                if occursin(gene_species[i], getStringElement(S_list, j-1))
                    temp_id = j-1
                    append!(gene_S_before, getVectorElement(C_S, temp_id))
                end
            end
        end
        for i = 1:nSpecies_gene
            for j = 1:nSpecies_boundary
                if occursin(gene_species[i], getStringElement(B_list, j-1))
                    temp_id = j-1
                    append!(gene_S_before, getVectorElement(C_B, temp_id))
                end
            end
        end
        freeVector(C_S)
        freeVector(C_B)
        for i = 1:nSpecies_gene
            append!(gene_S_perturb, gene_S_before[i]*perturbation_percentage)
        end
        S_after_up = zeros(nSpecies_gene, nSpecies)
        S_flat = zeros(nSpecies_gene, nSpecies)
        S_change = zeros(nSpecies_gene, nSpecies)
        for i = 1:nSpecies_gene
            for j = 1:nSpecies
                resetRR(rr)
                steadyState(rr)
                #steadyState_self(rr)
                for m = 1:nSpecies_floating
                    if occursin(gene_species[i], getStringElement(S_list, m-1))
                        temp_id = m-1
                        C_S = getFloatingSpeciesConcentrations(rr)
                        temp = getVectorElement(C_S, temp_id) + gene_S_perturb[i]
                        freeVector(C_S)
                        setFloatingSpeciesByIndex(rr, temp_id, temp)
                        steadyState(rr)
                        #steadyState_self(rr)
                        for n = 1: nSpecies_floating
                            if occursin("S$j", getStringElement(S_list, n-1))
                                temp_id_2 = n-1
                                C_S = getFloatingSpeciesConcentrations(rr)
                                S_after_up[i,j] = getVectorElement(C_S, temp_id_2)
                                freeVector(C_S)
                            end
                        end
                        for n = 1: nSpecies_boundary
                            if occursin("S$j", getStringElement(B_list, n-1))
                                temp_id_2 = n-1
                                C_B = getBoundarySpeciesConcentrations(rr)
                                S_after_up[i,j] = getVectorElement(C_B, temp_id_2)
                                freeVector(C_B)
                            end
                        end
                    end
                end
                for m = 1:nSpecies_boundary
                    if occursin(gene_species[i], getStringElement(B_list, m-1))
                        temp_id = m-1
                        C_B = getBoundarySpeciesConcentrations(rr)
                        temp = getVectorElement(C_B, temp_id) + gene_S_perturb[i]
                        freeVector(C_B)
                        setBoundarySpeciesByIndex(rr, temp_id, temp)
                        steadyState(rr)
                        #steadyState_self(rr)
                        for n = 1: nSpecies_floating
                            if occursin("S$j", getStringElement(S_list, n-1))
                                temp_id_2 = n-1
                                C_S = getFloatingSpeciesConcentrations(rr)
                                S_after_up[i,j] = getVectorElement(C_S, temp_id_2)
                                freeVector(C_S)
                            end
                        end
                        for n = 1: nSpecies_boundary
                            if occursin("S$j", getStringElement(B_list, n-1))
                                temp_id_2 = n-1
                                C_B = getBoundarySpeciesConcentrations(rr)
                                S_after_up[i,j] = getVectorElement(C_B, temp_id_2)
                                freeVector(C_B)
                            end
                        end
                        C_B = getBoundarySpeciesConcentrations(rr)
                        temp = getVectorElement(C_B, temp_id) - gene_S_perturb[i]
                        freeVector(C_B)
                        setBoundarySpeciesByIndex(rr, temp_id, temp)
                    end
                end
            end
        end

        for i = 1:nSpecies_gene
            for j = 1:nSpecies
                resetRR(rr)
                steadyState(rr)
                #steadyState_self(rr)
                for m = 1:nSpecies_floating
                    if occursin(gene_species[i], getStringElement(S_list, m-1))
                        temp_id = m-1
                        C_S = getFloatingSpeciesConcentrations(rr)
                        temp = getVectorElement(C_S, temp_id)
                        freeVector(C_S)
                        setFloatingSpeciesByIndex(rr, temp_id, temp)
                        steadyState(rr)
                        #steadyState_self(rr)
                        for n = 1: nSpecies_floating
                            if occursin("S$j", getStringElement(S_list, n-1))
                                temp_id_2 = n-1
                                C_S = getFloatingSpeciesConcentrations(rr)
                                S_flat[i,j] = getVectorElement(C_S, temp_id_2)
                                freeVector(C_S)
                            end
                        end
                        for n = 1: nSpecies_boundary
                            if occursin("S$j", getStringElement(B_list, n-1))
                                temp_id_2 = n-1
                                C_B = getBoundarySpeciesConcentrations(rr)
                                S_flat[i,j] = getVectorElement(C_B, temp_id_2)
                                freeVector(C_B)
                            end
                        end
                    end
                end
                for m = 1:nSpecies_boundary
                    if occursin(gene_species[i], getStringElement(B_list, m-1))
                        temp_id = m-1
                        C_B = getBoundarySpeciesConcentrations(rr)
                        temp = getVectorElement(C_B, temp_id)
                        freeVector(C_B)
                        setBoundarySpeciesByIndex(rr, temp_id, temp)
                        steadyState(rr)
                        #steadyState_self(rr)
                        for n = 1: nSpecies_floating
                            if occursin("S$j", getStringElement(S_list, n-1))
                                temp_id_2 = n-1
                                C_S = getFloatingSpeciesConcentrations(rr)
                                S_flat[i,j] = getVectorElement(C_S, temp_id_2)
                                freeVector(C_S)
                            end
                        end
                        for n = 1: nSpecies_boundary
                            if occursin("S$j", getStringElement(B_list, n-1))
                                temp_id_2 = n-1
                                C_B = getBoundarySpeciesConcentrations(rr)
                                S_flat[i,j] = getVectorElement(C_B, temp_id_2)
                                freeVector(C_B)
                            end
                        end
                        C_B = getBoundarySpeciesConcentrations(rr)
                        temp = getVectorElement(C_B, temp_id)
                        freeVector(C_B)
                        setBoundarySpeciesByIndex(rr, temp_id, temp)
                    end
                end
            end
        end

        for i = 1:nSpecies_gene
            for j = 1:nSpecies
                S_change[i,j] = S_after_up[i,j] - S_flat[i,j]
                if S_before[j] != 0.
                    S_change_scaled[i,j] = S_change[i,j]*S_before[i]/S_before[j]
                else
                    S_change_scaled[i,j] = NaN # here needs to change to n/a
                end
            end
        end
        freeStringArray(S_list)
        freeStringArray(B_list)
    catch e
        #println("no steady state")
        for i = 1: nSpecies_gene
            for j = 1: nSpecies
                S_change_scaled[i,j] = NaN
            end
        end
    end
    return S_change_scaled
end

function randomNetwork(rr, nSpecies, nSpecies_gene, nRxns_limitation)
    INPUT_RXN_MECH = ["UNICAT", "UNIBI", "BIUNI", "BIBI"]
    INPUT_RXN_MECH_WEIGHT = [0.25, 0.25, 0.25, 0.25]
    RXN_MECH = ["UNICAT", "UNIBI", "BIUNI", "BIBI", "CIRCLE", "DBCIRCLE"]
    RXN_MECH_WEIGHT = [0.2, 0.2, 0.2, 0.1, 0.2, 0.1]
    GN_RXN_MECH = ["UNICAT", "CIRCLE", "DBCIRCLE"]
    GN_RXN_MECH_WEIGHT = [0.4, 0.3, 0.3]


    generation_trial_threshold = 10

    species = ["S$i" for i = 1:nSpecies]
    gene_species = species[1:nSpecies_gene]

    rct_counter = zeros(nSpecies)
    prd_counter = zeros(nSpecies)


    generation_trial = 0

    valid_nRxns = false
    while valid_nRxns == false
        global rxn_counter = 0
        global rxn_specs = Dict{String, Any}()
        ids_tot = [] #to check if all the species are involved in reactions
        global species_ids = collect(1:nSpecies)
        global non_gene_species_ids = collect((nSpecies_gene+1):nSpecies)

        sbmlFile = "minimal.xml"
        f = open(sbmlFile)
        sbmlStr = read(f,String)
        close(f)
        loadSBML(rr, sbmlStr)
        addCompartment(rr, "compartment", 1.0, false)

        for s in species
            addSpecies(rr, s, "compartment", 0.1, "concentration", true)
        end

        addSpecies(rr, "S_in", "compartment", 0.1, "concentration", false)
        rxn_counter += 1
        rxn_mechanism = sample(INPUT_RXN_MECH, Weights(INPUT_RXN_MECH_WEIGHT))
        if rxn_mechanism == "UNICAT"
            parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
            ids = sample(species_ids, 2, replace = false)
            prds_id = ids[1]
            cats_id = ids[2]
            rv_ids = []
            append!(rv_ids, prds_id)
            append!(rv_ids, cats_id)
            species_ids = rv_specs(species_ids, rv_ids)
            non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
            rcts = ["S_in"]
            prds = ["S$prds_id"]
            cats = ["S$cats_id"]
            rxn_mech = ["S$cats_id * (kf_J$rxn_counter * S_in - kr_J$rxn_counter * S$prds_id) /(1 + S_in + S$prds_id)"]
            rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
        elseif rxn_mechanism == "UNIBI"
            parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
            ids = sample(non_gene_species_ids, 2, replace = false)
            prds_id  = ids[1]
            prds_id2 = ids[2]
            rv_ids = []
            append!(rv_ids, prds_id)
            append!(rv_ids, prds_id2)
            species_ids = rv_specs(species_ids, rv_ids)
            non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
            rcts = ["S_in"]
            prds = ["S$prds_id", "S$prds_id2"]
            cats = []
            rxn_mech = ["kf_J$rxn_counter * S_in - kr_J$rxn_counter * S$prds_id * S$prds_id2"]
            rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
        elseif rxn_mechanism == "BIUNI"
            parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
            ids = sample(non_gene_species_ids, 2, replace = false)
            rcts_id = ids[1]
            prds_id  = ids[2]
            rv_ids = []
            append!(rv_ids, rcts_id)
            append!(rv_ids, prds_id)
            species_ids = rv_specs(species_ids, rv_ids)
            non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
            rcts = ["S_in", "S$rcts_id"]
            prds = ["S$prds_id"]
            cats = []
            rxn_mech = ["kf_J$rxn_counter * S_in * S$rcts_id - kr_J$rxn_counter * S$prds_id"]
            rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
        else rxn_mechanism == "BIBI"
            parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
            ids = sample(non_gene_species_ids, 3, replace = false)
            rcts_id  = ids[1]
            prds_id  = ids[2]
            prds_id2 = ids[3]
            rv_ids = []
            append!(rv_ids, rcts_id)
            append!(rv_ids, prds_id)
            append!(rv_ids, prds_id2)
            species_ids = rv_specs(species_ids, rv_ids)
            non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
            rcts = ["S_in", "S$rcts_id"]
            prds = ["S$prds_id", "S$prds_id2"]
            cats = []
            rxn_mech = ["kf_J$rxn_counter * S_in * S$rcts_id - kr_J$rxn_counter * S$prds_id * S$prds_id2"]
            rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
        end
        setBoundary(rr, "S_in", true, false)
        append!(ids_tot, ids)

        addSpecies(rr, "S_out", "compartment", 0.1, "concentration", false)
        rxn_counter += 1

        rxn_mechanism == "CIRCLE"
        parameters1 = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
        parameters2 = ["kf_J$(rxn_counter+1)", "kr_J$(rxn_counter+1)"]
        ids = sample(species_ids, 3, replace = false)
        rcts_id = ids[1]
        cats_id = ids[2]
        cats_id2 = ids[3]
        rv_ids = []
        append!(rv_ids, rcts_id)
        append!(rv_ids, cats_id)
        append!(rv_ids, cats_id2)
        species_ids = rv_specs(species_ids, rv_ids)
        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
        rcts = ["S$rcts_id"]
        prds = ["S_out"]
        cats1 = ["S$cats_id"]
        cats2 = ["S$cats_id2"]
        rxn_mech1 = ["S$cats_id * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S_out) /(1 + S$rcts_id + S_out)"]
        rxn_mech2 = ["S$cats_id2 * (kf_J$(rxn_counter+1) * S_out - kr_J$(rxn_counter+1) * S$rcts_id) /(1 + S_out + S$rcts_id)"]
        rxn_specs["r$rxn_counter"]     = Dict{String, Array{String, 1}}("parameters" => parameters1, "rcts" => rcts, "prds" => prds, "cats" => cats1, "rxn_mech" => rxn_mech1)
        rxn_specs["r$(rxn_counter+1)"] = Dict{String, Array{String, 1}}("parameters" => parameters2, "rcts" => prds, "prds" => rcts, "cats" => cats2, "rxn_mech" => rxn_mech2)
        rxn_counter += 1

        setBoundary(rr, "S_out", false, false)
        append!(ids_tot, ids)


        specs_input = [] #species connected to input layer
        specs_output = [] #species connected to output layer
        # input layer prds can only be next layer's input or catalyzation
        # for CIRCLE and DBCIRCLE only can be the catalyzation
        # note that the cat was not considered here

        # output layer rcts and cats can be the closest upper layer's prds only
        rcts = rxn_specs["r2"]["rcts"]
        append!(specs_output, rcts)
        cats = rxn_specs["r2"]["cats"]
        append!(specs_output, cats)
        cats = rxn_specs["r3"]["cats"]
        append!(specs_output, cats)
        specs_output_selec = specs_output[rand(1:size(specs_output)[1])]

        species_ids_out = []
        append!(species_ids_out, species_ids)
        non_gene_species_ids_out = []
        append!(non_gene_species_ids_out, non_gene_species_ids)
        specs_output = rv_specs(specs_output, [specs_output_selec])
        if (size(specs_output)[1] > 0)
            for i = 1:nSpecies
                for j = 1:size(specs_output)[1]
                    if "S$i" == specs_output[j]
                        if "S$i" in gene_species
                            append!(species_ids_out, i)
                        else
                            append!(non_gene_species_ids_out, i)
                            append!(species_ids_out, i)
                        end
                    end
                end
            end
        end


        rxn_counter += 1
        if specs_output_selec in gene_species #rxn_mechanism == "UNICAT"
            parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
            ids = sample(species_ids, 2, replace = false)
            ids_out = []
            rcts_id = ids[1]
            cats_id = ids[2]
            rcts = ["S$rcts_id"]
            prds = [specs_output_selec]
            cats = ["S$cats_id"]
            rxn_mech = ["S$cats_id * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * $specs_output_selec) /(1 + S$rcts_id + $specs_output_selec)"]
            rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
        else
            rxn_mechanism = sample(INPUT_RXN_MECH, Weights(INPUT_RXN_MECH_WEIGHT))
            if rxn_mechanism == "UNICAT"
                parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                ids = sample(species_ids, 2, replace = false)
                ids_out = []
                rcts_id = ids[1]
                cats_id = ids[2]
                rcts = ["S$rcts_id"]
                prds = [specs_output_selec]
                cats = ["S$cats_id"]
                rxn_mech = ["S$cats_id * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * $specs_output_selec) /(1 + S$rcts_id + $specs_output_selec)"]
                rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
            elseif rxn_mechanism == "UNIBI"
                parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                ids = sample(non_gene_species_ids, 1, replace = false)
                non_gene_species_ids_out = rv_specs(non_gene_species_ids_out, ids)
                ids_out = sample(non_gene_species_ids_out, 1, replace = false)
                append!(non_gene_species_ids_out, ids)
                if rand() < 0.5
                    rcts_id  = ids[1]
                    prds_id2 = ids_out[1]
                    rcts = ["S$rcts_id"]
                    prds = [specs_output_selec, "S$prds_id2"]
                    cats = []
                    rxn_mech = ["kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * $specs_output_selec * S$prds_id2"]
                else
                    rcts_id  = ids[1]
                    prds_id  = ids_out[1]
                    rcts = ["S$rcts_id"]
                    prds = ["S$prds_id", specs_output_selec]
                    cats = []
                    rxn_mech = ["kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id * $specs_output_selec"]
                end
                rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
            elseif rxn_mechanism == "BIUNI"
                parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                ids = sample(non_gene_species_ids, 2, replace = false)
                ids_out = []
                rcts_id  = ids[1]
                rcts_id2 = ids[2]
                rcts = ["S$rcts_id", "S$rcts_id2"]
                prds = [specs_output_selec]
                cats = []
                rxn_mech = ["kf_J$rxn_counter * S$rcts_id * S$rcts_id2 - kr_J$rxn_counter * $specs_output_selec"]
                rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
            else rxn_mechanism == "BIBI"
                parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                ids = sample(non_gene_species_ids, 2, replace = false)
                non_gene_species_ids_out = rv_specs(non_gene_species_ids_out, ids)
                ids_out = sample(non_gene_species_ids_out, 1, replace = false)
                append!(non_gene_species_ids_out, ids)
                if rand() < 0.5
                    rcts_id  = ids[1]
                    rcts_id2 = ids[2]
                    prds_id2 = ids_out[1]
                    rcts = ["S$rcts_id", "S$rcts_id2"]
                    prds = [specs_output_selec, "S$prds_id2"]
                    cats = []
                    rxn_mech = ["kf_J$rxn_counter * S$rcts_id * S$rcts_id2 - kr_J$rxn_counter * $specs_output_selec * S$prds_id2"]
                else
                    rcts_id  = ids[1]
                    rcts_id2 = ids[2]
                    prds_id  = ids_out[1]
                    rcts = ["S$rcts_id", "S$rcts_id2"]
                    prds = ["S$prds_id", specs_output_selec]
                    cats = []
                    rxn_mech = ["kf_J$rxn_counter * S$rcts_id * S$rcts_id2 - kr_J$rxn_counter * S$prds_id * $specs_output_selec"]
                end
                rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
            end
        end
        append!(ids_tot, ids)
        append!(ids_tot, ids_out)




        prds = rxn_specs["r1"]["prds"]
        append!(specs_input, prds)



        all_species_involved = false
        # check if all species are involved
        nSpecies_involved = 0
        for i=1:nSpecies
            if i in ids_tot
                nSpecies_involved += 1
            end
        end
        if nSpecies_involved == nSpecies
            global all_species_involved = true
        end
        #println("nSpecies_involved_before:", nSpecies_involved)


        while all_species_involved == false
            # check if all species are involved
            nSpecies_involved = 0
            for i=1:nSpecies
                if i in ids_tot
                    nSpecies_involved += 1
                end
            end
            if nSpecies_involved == nSpecies
                global all_species_involved = true
            end
            #println("nSpecies_involved:", nSpecies_involved)


            # at least one of the specs_input should be connected to the next layer
            # random select one species from the prds
            #println(specs_input)
            specs_input_selec = specs_input[rand(1:size(specs_input)[1])]
            for i = 1: nSpecies
                if "S$i" == specs_input_selec
                    global specs_input_selec_ids = [i]
                end
            end


            species_ids_in = []
            append!(species_ids_in, species_ids)
            non_gene_species_ids_in = []
            append!(non_gene_species_ids_in, non_gene_species_ids)
            specs_input = rv_specs(specs_input, [specs_input_selec])
            if (size(specs_input)[1] > 0)
                for i = 1:nSpecies
                    for j = 1:size(specs_input)[1]
                        if "S$i" == specs_input[j]
                            if "S$i" in gene_species
                                append!(species_ids_in, i)
                            else
                                append!(non_gene_species_ids_in, i)
                                append!(species_ids_in, i)
                            end
                        end
                    end
                end
            end


            rxn_counter_start = rxn_counter
            rxn_counter += 1
            if specs_input_selec in gene_species
                rxn_mechanism = sample(GN_RXN_MECH, Weights(GN_RXN_MECH_WEIGHT))
                if rxn_mechanism == "UNICAT"
                    parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                    try
                        ids = sample(species_ids, 1, replace = false)
                        species_ids_in = rv_specs(species_ids_in, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                        append!(species_ids_in, ids)
                    catch e
                        temp_ids = collect(1:nSpecies)
                        temp_ids = rv_specs(temp_ids, specs_input_selec_ids)
                        ids = sample(temp_ids, 1, replace = false)
                        species_ids_in = rv_specs(temp_ids, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                    end
                    if rand() < 0.5
                        prds_id = ids[1]
                        cats_id = ids_in[1]
                        rv_ids = []
                        append!(rv_ids, prds_id)
                        append!(rv_ids, cats_id2)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = [specs_input_selec]
                        prds = ["S$prds_id"]
                        cats = ["S$cats_id"]
                        rxn_mech = ["S$cats_id * (kf_J$rxn_counter * $specs_input_selec - kr_J$rxn_counter * S$prds_id) /(1 + $specs_input_selec + S$prds_id)"]
                    else
                        rcts_id = ids_in[1]
                        prds_id = ids[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = ["S$rcts_id"]
                        prds = ["S$prds_id"]
                        cats = [specs_input_selec]
                        rxn_mech = ["$specs_input_selec * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                    end
                    rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
                elseif rxn_mechanism == "CIRCLE"
                    parameters1 = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                    parameters2 = ["kf_J$(rxn_counter+1)", "kr_J$(rxn_counter+1)"]
                    try
                        ids = sample(species_ids, 2, replace = false)
                        species_ids_in = rv_specs(species_ids_in, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                        append!(species_ids_in, ids)
                    catch
                        temp_ids = collect(1:nSpecies)
                        temp_ids = rv_specs(temp_ids, specs_input_selec_ids)
                        ids = sample(temp_ids, 2, replace = false)
                        species_ids_in = rv_specs(temp_ids, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                    end
                    if rand() < 0.5
                        rcts_id = ids[1]
                        prds_id = ids[2]
                        cats_id2 = ids_in[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, cats_id2)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = ["S$rcts_id"]
                        prds = ["S$prds_id"]
                        cats1 = [specs_input_selec]
                        cats2 = ["S$cats_id2"]
                        rxn_mech1 = ["$specs_input_selec * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                        rxn_mech2 = ["S$cats_id2 * (kf_J$(rxn_counter+1) * S$prds_id - kr_J$(rxn_counter+1) * S$rcts_id) /(1 + S$prds_id + S$rcts_id)"]
                    else
                        rcts_id = ids[1]
                        prds_id = ids[2]
                        cats_id = ids_in[1]
                        rcts = ["S$rcts_id"]
                        prds = ["S$prds_id"]
                        cats1 = ["S$cats_id"]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, cats_id)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        cats2 = [specs_input_selec]
                        rxn_mech1 = ["S$cats_id * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                        rxn_mech2 = ["$specs_input_selec * (kf_J$(rxn_counter+1) * S$prds_id - kr_J$(rxn_counter+1) * S$rcts_id) /(1 + S$prds_id + S$rcts_id)"]
                    end
                    rxn_specs["r$rxn_counter"]     = Dict{String, Array{String, 1}}("parameters" => parameters1, "rcts" => rcts, "prds" => prds, "cats" => cats1, "rxn_mech" => rxn_mech1)
                    rxn_specs["r$(rxn_counter+1)"] = Dict{String, Array{String, 1}}("parameters" => parameters2, "rcts" => prds, "prds" => rcts, "cats" => cats2, "rxn_mech" => rxn_mech2)
                    rxn_counter += 1
                else rxn_mechanism == "DBCIRCLE"
                    parameters1 = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                    parameters2 = ["kf_J$(rxn_counter+1)", "kr_J$(rxn_counter+1)"]
                    parameters3 = ["kf_J$(rxn_counter+2)", "kr_J$(rxn_counter+2)"]
                    parameters4 = ["kf_J$(rxn_counter+3)", "kr_J$(rxn_counter+3)"]
                    try
                        ids = sample(species_ids, 3, replace = false)
                        species_ids_in = rv_specs(species_ids_in, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                        append!(species_ids_in, ids)
                    catch
                        temp_ids = collect(1:nSpecies)
                        temp_ids = rv_specs(temp_ids, specs_input_selec_ids)
                        ids = sample(temp_ids, 3, replace = false)
                        species_ids_in = rv_specs(temp_ids, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                    end
                    if rand() < 0.5
                        rcts_id  = ids[1]
                        prds_id  = ids[2]
                        prds_id2 = ids[3]
                        cats_id2 = ids_in[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, prds_id2)
                        append!(rv_ids, cats_id2)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts1 = ["S$rcts_id"]
                        prds1 = ["S$prds_id"]
                        prds2 = ["S$prds_id2"]
                        cats1 = [specs_input_selec]
                        cats2 = ["S$cats_id2"]
                        rxn_mech1 = ["$specs_input_selec  * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                        rxn_mech2 = ["$specs_input_selec  * (kf_J$(rxn_counter+1) * S$prds_id - kr_J$(rxn_counter+1) * S$prds_id2) /(1 + S$prds_id + S$prds_id2)"]
                        rxn_mech3 = ["S$cats_id2 * (kf_J$(rxn_counter+2) * S$prds_id2 - kr_J$(rxn_counter+2) * S$prds_id) /(1 + S$prds_id2 + S$prds_id)"]
                        rxn_mech4 = ["S$cats_id2 * (kf_J$(rxn_counter+3) * S$prds_id - kr_J$(rxn_counter+3) * S$rcts_id) /(1 + S$prds_id + S$rcts_id)"]
                    else
                        rcts_id  = ids[1]
                        prds_id  = ids[2]
                        prds_id2 = ids[3]
                        cats_id  = ids_in[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, prds_id2)
                        append!(rv_ids, cats_id)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts1 = ["S$rcts_id"]
                        prds1 = ["S$prds_id"]
                        prds2 = ["S$prds_id2"]
                        cats1 = ["S$cats_id"]
                        cats2 = [specs_input_selec]
                        rxn_mech1 = ["S$cats_id  * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                        rxn_mech2 = ["S$cats_id  * (kf_J$(rxn_counter+1) * S$prds_id - kr_J$(rxn_counter+1) * S$prds_id2) /(1 + S$prds_id + S$prds_id2)"]
                        rxn_mech3 = ["$specs_input_selec * (kf_J$(rxn_counter+2) * S$prds_id2 - kr_J$(rxn_counter+2) * S$prds_id) /(1 + S$prds_id2 + S$prds_id)"]
                        rxn_mech4 = ["$specs_input_selec * (kf_J$(rxn_counter+3) * S$prds_id - kr_J$(rxn_counter+3) * S$rcts_id) /(1 + S$prds_id + S$rcts_id)"]
                    end
                    rxn_specs["r$rxn_counter"]     = Dict{String, Array{String, 1}}("parameters" => parameters1, "rcts" => rcts1, "prds" => prds1, "cats" => cats1, "rxn_mech" => rxn_mech1)
                    rxn_specs["r$(rxn_counter+1)"] = Dict{String, Array{String, 1}}("parameters" => parameters2, "rcts" => prds1, "prds" => prds2, "cats" => cats1, "rxn_mech" => rxn_mech2)
                    rxn_specs["r$(rxn_counter+2)"] = Dict{String, Array{String, 1}}("parameters" => parameters3, "rcts" => prds2, "prds" => prds1, "cats" => cats2, "rxn_mech" => rxn_mech3)
                    rxn_specs["r$(rxn_counter+3)"] = Dict{String, Array{String, 1}}("parameters" => parameters4, "rcts" => prds1, "prds" => rcts1, "cats" => cats2, "rxn_mech" => rxn_mech4)
                    rxn_counter += 3
                end

            else # specs_input_selec not in gene_species
                rxn_mechanism = sample(RXN_MECH, Weights(RXN_MECH_WEIGHT))
                if rxn_mechanism == "UNICAT"
                    parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                    try
                        ids = sample(species_ids, 1, replace = false)
                        species_ids_in = rv_specs(species_ids_in, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                        append!(species_ids_in, ids)
                    catch
                        temp_ids = collect(1:nSpecies)
                        temp_ids = rv_specs(temp_ids, specs_input_selec_ids)
                        ids = sample(temp_ids, 1, replace = false)
                        species_ids_in = rv_specs(temp_ids, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                    end

                    if rand() < 0.5
                        prds_id = ids[1]
                        cats_id = ids_in[1]
                        rv_ids = []
                        append!(rv_ids, prds_id)
                        append!(rv_ids, cats_id)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = [specs_input_selec]
                        prds = ["S$prds_id"]
                        cats = ["S$cats_id"]
                        rxn_mech = ["S$cats_id * (kf_J$rxn_counter * $specs_input_selec - kr_J$rxn_counter * S$prds_id) /(1 + $specs_input_selec + S$prds_id)"]
                    else
                        rcts_id = ids_in[1]
                        prds_id = ids[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = ["S$rcts_id"]
                        prds = ["S$prds_id"]
                        cats = [specs_input_selec]
                        rxn_mech = ["$specs_input_selec * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                    end
                    rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
                elseif rxn_mechanism == "UNIBI"
                    parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                    try
                        ids = sample(non_gene_species_ids, 2, replace = false)
                    catch
                        temp_ids = collect((nSpecies_gene+1):nSpecies)
                        temp_ids = rv_specs(temp_ids, specs_input_selec_ids)
                        ids = sample(temp_ids, 2, replace = false)
                    end
                    ids_in = []
                    prds_id  = ids[1]
                    prds_id2 = ids[2]
                    rv_ids = []
                    append!(rv_ids, prds_id)
                    append!(rv_ids, prds_id2)
                    species_ids = rv_specs(species_ids, rv_ids)
                    non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                    rcts = [specs_input_selec]
                    prds = ["S$prds_id", "S$prds_id2"]
                    cats = []
                    rxn_mech = ["kf_J$rxn_counter * $specs_input_selec - kr_J$rxn_counter * S$prds_id * S$prds_id2"]
                    rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
                elseif rxn_mechanism == "BIUNI"
                    parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                    try
                        ids = sample(non_gene_species_ids, 1, replace = false)
                        non_gene_species_ids_in = rv_specs(non_gene_species_ids_in, ids)
                        ids_in = sample(non_gene_species_ids_in, 1, replace = false)
                        append!(non_gene_species_ids_in, ids)
                    catch
                        temp_ids = collect((nSpecies_gene+1):nSpecies)
                        temp_ids = rv_specs(temp_ids, specs_input_selec_ids)
                        ids = sample(temp_ids, 1, replace = false)
                        species_ids_in = rv_specs(temp_ids, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                    end
                    if rand() < 0.5
                        rcts_id2 = ids_in[1]
                        prds_id  = ids[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id2)
                        append!(rv_ids, prds_id)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = [specs_input_selec, "S$rcts_id2"]
                        prds = ["S$prds_id"]
                        cats = []
                        rxn_mech = ["kf_J$rxn_counter * $specs_input_selec * S$rcts_id2 - kr_J$rxn_counter * S$prds_id"]
                    else
                        rcts_id  = ids_in[1]
                        prds_id  = ids[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = ["S$rcts_id", specs_input_selec]
                        prds = ["S$prds_id"]
                        cats = []
                        rxn_mech = ["kf_J$rxn_counter * S$rcts_id * $specs_input_selec - kr_J$rxn_counter * S$prds_id"]
                    end
                    rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
                elseif rxn_mechanism == "BIBI"
                    parameters = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                    try
                        ids = sample(non_gene_species_ids, 2, replace = false)
                        non_gene_species_ids_in = rv_specs(non_gene_species_ids_in, ids)
                        ids_in = sample(non_gene_species_ids_in, 1, replace = false)
                        append!(non_gene_species_ids_in, ids)
                    catch
                        temp_ids = collect((nSpecies_gene+1):nSpecies)
                        temp_ids = rv_specs(temp_ids, specs_input_selec_ids)
                        ids = sample(temp_ids, 2, replace = false)
                        species_ids_in = rv_specs(temp_ids, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                    end
                    if rand() < 0.5
                        rcts_id2 = ids_in[1]
                        prds_id  = ids[1]
                        prds_id2 = ids[2]
                        rv_ids = []
                        append!(rv_ids, rcts_id2)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, prds_id2)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = [specs_input_selec, "S$rcts_id2"]
                        prds = ["S$prds_id", "S$prds_id2"]
                        cats = []
                        rxn_mech = ["kf_J$rxn_counter * $specs_input_selec * S$rcts_id2 - kr_J$rxn_counter * S$prds_id * S$prds_id2"]
                    else
                        rcts_id  = ids_in[1]
                        prds_id  = ids[1]
                        prds_id2 = ids[2]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, prds_id2)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = ["S$rcts_id", specs_input_selec]
                        prds = ["S$prds_id", "S$prds_id2"]
                        cats = []
                        rxn_mech = ["kf_J$rxn_counter * S$rcts_id * $specs_input_selec - kr_J$rxn_counter * S$prds_id * S$prds_id2"]
                    end
                    rxn_specs["r$rxn_counter"] = Dict{String, Array{String, 1}}("parameters" => parameters, "rcts" => rcts, "prds" => prds, "cats" => cats, "rxn_mech" => rxn_mech)
                elseif rxn_mechanism == "CIRCLE"
                    parameters1 = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                    parameters2 = ["kf_J$(rxn_counter+1)", "kr_J$(rxn_counter+1)"]
                    try
                        ids = sample(species_ids, 2, replace = false)
                        species_ids_in = rv_specs(species_ids_in, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                        append!(species_ids_in, ids)
                    catch
                        temp_ids = collect((nSpecies_gene+1):nSpecies)
                        temp_ids = rv_specs(temp_ids, specs_input_selec_ids)
                        ids = sample(temp_ids, 2, replace = false)
                        species_ids_in = rv_specs(temp_ids, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                    end
                    if rand() < 0.5
                        rcts_id = ids[1]
                        prds_id = ids[2]
                        cats_id2 = ids_in[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, cats_id2)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = ["S$rcts_id"]
                        prds = ["S$prds_id"]
                        cats1 = [specs_input_selec]
                        cats2 = ["S$cats_id2"]
                        rxn_mech1 = ["$specs_input_selec * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                        rxn_mech2 = ["S$cats_id2 * (kf_J$(rxn_counter+1) * S$prds_id - kr_J$(rxn_counter+1) * S$rcts_id) /(1 + S$prds_id + S$rcts_id)"]
                    else
                        rcts_id = ids[1]
                        prds_id = ids[2]
                        cats_id = ids_in[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, cats_id)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts = ["S$rcts_id"]
                        prds = ["S$prds_id"]
                        cats1 = ["S$cats_id"]
                        cats2 = [specs_input_selec]
                        rxn_mech1 = ["S$cats_id * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                        rxn_mech2 = ["$specs_input_selec * (kf_J$(rxn_counter+1) * S$prds_id - kr_J$(rxn_counter+1)* S$rcts_id) /(1 + S$prds_id + S$rcts_id)"]
                    end
                    rxn_specs["r$rxn_counter"]     = Dict{String, Array{String, 1}}("parameters" => parameters1, "rcts" => rcts, "prds" => prds, "cats" => cats1, "rxn_mech" => rxn_mech1)
                    rxn_specs["r$(rxn_counter+1)"] = Dict{String, Array{String, 1}}("parameters" => parameters2, "rcts" => prds, "prds" => rcts, "cats" => cats2, "rxn_mech" => rxn_mech2)
                    rxn_counter += 1
                else rxn_mechanism == "DBCIRCLE"
                    parameters1 = ["kf_J$rxn_counter", "kr_J$rxn_counter"]
                    parameters2 = ["kf_J$(rxn_counter+1)", "kr_J$(rxn_counter+1)"]
                    parameters3 = ["kf_J$(rxn_counter+2)", "kr_J$(rxn_counter+2)"]
                    parameters4 = ["kf_J$(rxn_counter+3)", "kr_J$(rxn_counter+3)"]
                    try
                        ids = sample(species_ids, 3, replace = false)
                        species_ids_in = rv_specs(species_ids_in, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                        append!(species_ids_in, ids)
                    catch
                        temp_ids = collect(1:nSpecies)
                        temp_ids = rv_specs(temp_ids, specs_input_selec_ids)
                        ids = sample(temp_ids, 3, replace = false)
                        species_ids_in = rv_specs(temp_ids, ids)
                        ids_in = sample(species_ids_in, 1, replace = false)
                    end
                    if rand() < 0.5
                        rcts_id  = ids[1]
                        prds_id  = ids[2]
                        prds_id2 = ids[3]
                        cats_id2 = ids_in[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, prds_id2)
                        append!(rv_ids, cats_id2)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts1 = ["S$rcts_id"]
                        prds1 = ["S$prds_id"]
                        prds2 = ["S$prds_id2"]
                        cats1 = [specs_input_selec]
                        cats2 = ["S$cats_id2"]
                        rxn_mech1 = ["$specs_input_selec  * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                        rxn_mech2 = ["$specs_input_selec  * (kf_J$(rxn_counter+1) * S$prds_id - kr_J$(rxn_counter+1) * S$prds_id2) /(1 + S$prds_id + S$prds_id2)"]
                        rxn_mech3 = ["S$cats_id2 * (kf_J$(rxn_counter+2) * S$prds_id2 - kr_J$(rxn_counter+2) * S$prds_id) /(1 + S$prds_id2 + S$prds_id)"]
                        rxn_mech4 = ["S$cats_id2 * (kf_J$(rxn_counter+3) * S$prds_id - kr_J$(rxn_counter+3) * S$rcts_id) /(1 + S$prds_id + S$rcts_id)"]
                    else
                        rcts_id  = ids[1]
                        prds_id  = ids[2]
                        prds_id2 = ids[3]
                        cats_id  = ids_in[1]
                        rv_ids = []
                        append!(rv_ids, rcts_id)
                        append!(rv_ids, prds_id)
                        append!(rv_ids, prds_id2)
                        append!(rv_ids, cats_id)
                        species_ids = rv_specs(species_ids, rv_ids)
                        non_gene_species_ids = rv_specs(non_gene_species_ids, rv_ids)
                        rcts1 = ["S$rcts_id"]
                        prds1 = ["S$prds_id"]
                        prds2 = ["S$prds_id2"]
                        cats1 = ["S$cats_id"]
                        cats2 = [specs_input_selec]
                        rxn_mech1 = ["S$cats_id  * (kf_J$rxn_counter * S$rcts_id - kr_J$rxn_counter * S$prds_id) /(1 + S$rcts_id + S$prds_id)"]
                        rxn_mech2 = ["S$cats_id  * (kf_J$(rxn_counter+1) * S$prds_id - kr_J$(rxn_counter+1) * S$prds_id2) /(1 + S$prds_id + S$prds_id2)"]
                        rxn_mech3 = ["$specs_input_selec * (kf_J$(rxn_counter+2) * S$prds_id2 - kr_J$(rxn_counter+2) * S$prds_id) /(1 + S$prds_id2 + S$prds_id)"]
                        rxn_mech4 = ["$specs_input_selec * (kf_J$(rxn_counter+3) * S$prds_id - kr_J$(rxn_counter+3) * S$rcts_id) /(1 + S$prds_id + S$rcts_id)"]
                    end
                    rxn_specs["r$rxn_counter"]     = Dict{String, Array{String, 1}}("parameters" => parameters1, "rcts" => rcts1, "prds" => prds1, "cats" => cats1, "rxn_mech" => rxn_mech1)
                    rxn_specs["r$(rxn_counter+1)"] = Dict{String, Array{String, 1}}("parameters" => parameters2, "rcts" => prds1, "prds" => prds2, "cats" => cats1, "rxn_mech" => rxn_mech2)
                    rxn_specs["r$(rxn_counter+2)"] = Dict{String, Array{String, 1}}("parameters" => parameters3, "rcts" => prds2, "prds" => prds1, "cats" => cats2, "rxn_mech" => rxn_mech3)
                    rxn_specs["r$(rxn_counter+3)"] = Dict{String, Array{String, 1}}("parameters" => parameters4, "rcts" => prds1, "prds" => rcts1, "cats" => cats2, "rxn_mech" => rxn_mech4)
                    rxn_counter += 3
                end
            end

            append!(ids_tot, ids)
            append!(ids_tot, ids_in)

            rxn_counter_end = rxn_counter
            specs_input = []
            for i = (rxn_counter_start+1):rxn_counter_end
                prds = rxn_specs["r$i"]["prds"]
                append!(specs_input, prds)
                if size(specs_input)[1] == 4 # if select "DBCIRCLE", remove the first species
                    deleteat!(specs_input, 1)
                end
            end

        end
        # last prds to connect to next output layer with its rcts or cats

        specs_r4 = []
        rcts = rxn_specs["r4"]["rcts"]
        cats = rxn_specs["r4"]["cats"]
        append!(specs_r4, rcts)
        append!(specs_r4, cats)

        rand_specs_input = rand(1: size(specs_input)[1])
        rand_specs_r4 = rand(1: size(specs_r4)[1])
        specs_r4[rand_specs_r4] = specs_input[rand_specs_input]

        if rxn_counter <= nRxns_limitation
            valid_nRxns = true

            # counter the number of effective steps
            #S_in is in reaction r1, S_out is in reaction r2 and r3
            #step 1: does r1 and r2+r3 have common species?
            specs_in = []
            rcts = rxn_specs["r1"]["rcts"]
            prds = rxn_specs["r1"]["prds"]
            cats = rxn_specs["r1"]["cats"]
            specs_in = append!(specs_in, rcts)
            specs_in = append!(specs_in, prds)
            specs_in = append!(specs_in, cats)

            specs_out = []
            rcts = rxn_specs["r2"]["rcts"]
            prds = rxn_specs["r2"]["prds"]
            cats = rxn_specs["r2"]["cats"]
            cats2= rxn_specs["r3"]["cats"]
            specs_out = append!(specs_out, rcts)
            specs_out = append!(specs_out, prds)
            specs_out = append!(specs_out, cats)
            specs_out = append!(specs_out, cats2)

            common_specs = intersect(specs_in, specs_out)
            num_common_specs = size(common_specs)[1]

            eff_rxs = Array{Any,1}
            eff_rxs_num = 3 # 3 = r1(S_in)+r2(S_out)+r3(S_out)
            eff_rxs = ["r1", "r2", "r3"]

            rxs_in  = []
            rxs_out = []
            trial = 1
            while num_common_specs == 0 && trial < nRxns_limitation
                trial += 1
                rxs_in  = []
                rxs_out = []
                for i = 4:rxn_counter # r1 includes S_in, r2 and r3 include S_out
                    specs = []
                    rcts = rxn_specs["r$i"]["rcts"]
                    prds = rxn_specs["r$i"]["prds"]
                    cats = rxn_specs["r$i"]["cats"]
                    specs = append!(specs, rcts)
                    specs = append!(specs, prds)
                    specs = append!(specs, cats)
                    if size(intersect(specs_in, specs))[1] > 0
                        append!(rxs_in, ["r$i"])
                    end
                    if size(intersect(specs_out, specs))[1] > 0
                        append!(rxs_out, ["r$i"])
                    end
                end

                specs_in = []
                specs_out = []
                for j = 1:size(rxs_in)[1]
                    rcts = rxn_specs[rxs_in[j]]["rcts"]
                    prds = rxn_specs[rxs_in[j]]["prds"]
                    cats = rxn_specs[rxs_in[j]]["cats"]
                    specs_in = append!(specs_in, rcts)
                    specs_in = append!(specs_in, prds)
                    specs_in = append!(specs_in, cats)
                end
                for j = 1:size(rxs_out)[1]
                    rcts = rxn_specs[rxs_out[j]]["rcts"]
                    prds = rxn_specs[rxs_out[j]]["prds"]
                    cats = rxn_specs[rxs_out[j]]["cats"]
                    specs_out = append!(specs_out, rcts)
                    specs_out = append!(specs_out, prds)
                    specs_out = append!(specs_out, cats)
                end

                common_specs = intersect(specs_in, specs_out)
                num_common_specs = size(common_specs)[1]

            end
            if trial != nRxns_limitation
                global eff_steps = trial
                #println(eff_steps)
                for i = 1: rxn_counter
                    parameters = rxn_specs["r$i"]["parameters"]
                    parameters_len = size(parameters)[1]
                    for j = 1:parameters_len
                        addParameter(rr, parameters[j], 0.1, false)
                    end
                end

                for i = 1: rxn_counter
                    rcts = rxn_specs["r$i"]["rcts"]
                    prds = rxn_specs["r$i"]["prds"]
                    rxn_mech = rxn_specs["r$i"]["rxn_mech"]
                    i == rxn_counter ? regen = true : regen = false
                    addReaction(rr, "r$i", rcts, prds, rxn_mech[1], regen) #here pay attention to true and false
                end



                sbml_sample = getCurrentSBML(rr)
                f_sample = open("randomNetwork.xml", "w+");
                write(f_sample, sbml_sample)
                close(f_sample)


            else
                global eff_steps = 0
                #println(eff_steps)
                e = ErrorException("Incomplete network")
                throw(e)
            end
        else
            generation_trial += 1
            if generation_trial >= generation_trial_threshold
                e = ErrorException("Failure to generate due to too small nRxns_limiation")
                #println("generation_trial:", generation_trial)
                throw(e)
            end
        end
    end
    return (rr, rxn_specs, eff_steps) ## rr is the network saved in roadrunner
end

function negativeConcentration(rr)
    C_S = getFloatingSpeciesConcentrations(rr)
    nSpecies_boundary = getNumberOfBoundarySpecies(rr)
    nSpecies_floating = getNumberOfFloatingSpecies(rr)
    neg_c = 0
    for i = 0:(nSpecies_floating-1)
        C_element = getVectorElement(C_S, i)
        if C_element[1] < 0
            neg_c = 1
        end
    end
    freeVector(C_S)
    C_B = getBoundarySpeciesConcentrations(rr)
    for i = 0:(nSpecies_boundary-1)
        C_element = getVectorElement(C_B, i)
        if C_element[1] < 0
            neg_c = 1
        end
    end
    freeVector(C_B)
    return neg_c
end

# Generate the ground truth model
#rr_real = createRRInstance()

@time begin

    goodSample = 0
    while goodSample == 0

        global species = ["S$i" for i = 1:nSpecies]
        global gene_species = species[1:nSpecies_gene]
    ## random network generation
        global rr_real = createRRInstance()
        try
            (rr_real, rxn_specs, eff_steps) = randomNetwork(rr_real, nSpecies, nSpecies_gene, nRxns_limitation)

            P_num = getNumberOfGlobalParameters(rr_real)
            nSpecies_boundary = getNumberOfBoundarySpecies(rr_real)
            nSpecies_floating = getNumberOfFloatingSpecies(rr_real)
            #assign random values to spieces and parameters
            for i = 0:(nSpecies_floating-1)
                setFloatingSpeciesInitialConcentrationByIndex(rr_real, i, rnd_species*rand()) # random number [0,1)
            end
            for i = 0:(nSpecies_boundary-1)
                setBoundarySpeciesByIndex(rr_real, i, rnd_species*rand())
            end
            for i = 0:(P_num-1)
                setGlobalParameterByIndex(rr_real, i, rnd_parameter*rand())
            end
            setConfigInt("LOADSBMLOPTIONS_CONSERVED_MOIETIES", 1)
            # Check if the ground truth model has a steady state
            try
                steadyState(rr_real)
                #steadyState_self(rr_real)
                #check if it is a valid steadystate
                neg_c = negativeConcentration(rr_real)
                if neg_c == 0
                    C_B = getBoundarySpeciesConcentrations(rr_real)
                    C_Sin = getVectorElement(C_B, nSpecies_boundary-1)
                    C_S = getFloatingSpeciesConcentrations(rr_real)
                    C_Sout = getVectorElement(C_S, nSpecies_floating-1)
                    freeVector(C_B)
                    freeVector(C_S)
                    setBoundarySpeciesByIndex(rr_real, nSpecies_boundary-1, C_Sin*concentration_perturb)
                    setConfigInt("LOADSBMLOPTIONS_CONSERVED_MOIETIES", 1)
                    try
                        steadyState(rr_real)
                        #steadyState_self(rr_real)
                        C_S = getFloatingSpeciesConcentrations(rr_real)
                        C_Sout_after = getVectorElement(C_S, nSpecies_floating-1)
                        C_Sout_change = C_Sout_after - C_Sout
                        freeVector(C_S)
                        if (abs.(C_Sout_change) > 0 && eff_steps >= 3)
                            #println("C_out:", C_Sout)
                            #println("C_Sout_change:", C_Sout_change)
                            #println("eff_steps:", eff_steps)
                            if perturbation_flag == true
                                #global F_real = speciesPerturbationMatrix(rr_real, nSpecies_gene, perturbation_percentage) #up_and_down case is quite sparse
                                global F_real = speciesPerturbationMatrix_up_only(rr_real, nSpecies_gene, perturbation_percentage)
                                nan_inf = 0
                                for x = 1:nSpecies_gene
                                    for y = 1:nSpecies
                                        if isnan(F_real[x,y]) || isinf(F_real[x,y])
                                            nan_inf = 1
                                        end
                                    end
                                end
                                if nan_inf == 0
                                    for x = 1:nSpecies_gene
                                        for y = 1:nSpecies
                                            if abs.(F_real[x,y]) < 1e-12
                                                F_real[x,y] = 0.
                                            end
                                        end
                                    end
                                    if F_real != zeros(nSpecies_gene, nSpecies)
                                        # make sure if only very few elements are zeros which could work for this algorithm
                                        if noise
                                            with_noise = (F_real[x,y] + rand(Normal(0., abs_noise), 1)[1]+
                                            rand(Normal(0, abs.(F_real[x,y]*rel_noise)), 1)[1])
                                            F_real[x,y] = with_noise
                                        end
                                        global goodSample = 1
                                        #println(rxn_specs)
                                        sbml_sample = getCurrentSBML(rr_real)
                                        f_sample = open("sampleNetwork.xml", "w+");
                                        write(f_sample, sbml_sample)
                                        close(f_sample)
                                        println("a good model!")
                                        freeRRInstance(rr_real)
                                    end
                                else
                                    println("Error message: perturbation matrix has infinities")
                                end
                            else
                                global goodSample = 1
                                sbml_sample = getCurrentSBML(rr_real)
                                f_sample = open("sampleNetwork.xml", "w+");
                                write(f_sample, sbml_sample)
                                close(f_sample)
                                println("a good model without considering perturbation matrix!")
                                freeRRInstance(rr_real)
                            end
                        end
                    catch e
                        continue
                    end
                else
                    println("Error message: negative concentrations")
                end
            catch e
                continue
            end
        catch e
            println(e)
        end
    end

end
