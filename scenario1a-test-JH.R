# Scenario 1
library(prioritizr)
library(sf)
library(terra)
library(vegan)
library(cluster)
library(raster)
library(gurobi)
library(slam)


# load planning unit data
tfc_costs <- rast("input-data//total_forest_cover_25832.tif")
tfc_costs

# creating a new raster with constant costs
tfc_const_costs <- (tfc_costs*0) + 1
tfc_const_costs

# loading conservation features
existing_spa <- rast("input-data/Forest_strictly_protected_25832.tif")
N2000 <- rast("input-data/Habitat_directive_FFH_25832.tif")
fht <- rast("input-data/forest_habitat_types_reclas_25832.tif")
pwa <- rast("input-data/PWA_3000_NRW_25832.tif")
state_f <- rast("input-data/State_forest_25832.tif")

# loading the high vitality decreased layer
vit_dec <- rast("input-data/vitality_highly_decreased_25832.tif")

# setting value 0.25 for all the cells
reclass_matrix <- matrix(c(3, 0.25), ncol = 2, byrow = TRUE)
vit_dec <-  classify(vit_dec, reclass_matrix)

# update values in tfc feature to consider it as a conservation feature
tfc_feature <- rast("input-data/total_forest_cover_25832.tif")
tfc_feature <- terra::mask(
  tfc_feature,
  mask = (tfc_feature > 0.5) & (vit_dec == 0.25),
  maskvalues = 1,
  updatevalue = 0.25
)
names(tfc_feature) <- "tfc_feature"

# create a binary stack for fht raster
bstacked_fht <- binary_stack(fht)

# set names to keep track of all the different fht
names(bstacked_fht) <- paste0("class_", seq_len(nlyr(bstacked_fht)))

# remove layers with only zeros
bstacked_fht <- bstacked_fht[[which(global(bstacked_fht, "max", na.rm = TRUE)[[1]] > 0.5)]]

# I need to change bstacked_fht layers values in this way: WHEN 'NULL' THEN 'NULL'; WHEN '0' THEN '0'; WHEN '1'THEN '1' IF not overlap with vit_dec
# or '0.25' IF overlap with vit_dec
# or in other words, replace the values only when bstacked_fht[[i]] > 0.5 and vit_dec > 0.20

# trying this way:
modified_bstacked_fht <-  terra::rast(lapply(as.list(bstacked_fht), function(x) {
  terra::mask(x, mask = (x > 0.5) & (vit_dec == 0.25), maskvalues = 1, updatevalue = 0.25)
}))


# creating the conservation feature object
cons_feat_1 <- c(
    modified_bstacked_fht, existing_spa, pwa, state_f, N2000, tfc_feature
)
cons_feat_1


# Adding targets
# setting different relative targets
targets <- c(
  rep(0.3, nlyr(modified_bstacked_fht)), ## >= 30% coverage of each forest type
  0,                                     ## >= 0% coverage of existing_spa
  0,                                     ## >= 0% coverage of pwa
  0,                                     ## >= 0% coverage of state_f
  0.3,                                    ## >= 30% coverage of N2000,
  1                                      ## >= 100% tfc_feature
)


# adding targets to the problem
p1 <-
  problem(tfc_const_costs, cons_feat_1) %>%
  add_min_shortfall_objective(budget = 90092) %>%
  add_relative_targets(targets) %>%
  add_gurobi_solver(gap = 0) %>%
  add_binary_decisions()

p1


# Add constraints

# preparing data
# trying to get the not_state_forest layer by subtraction between total forest cover and state forest. I need to change the NA values to 0


not_state_f <- tfc_const_costs - state_f
not_state_f[is.na(not_state_f)] <- 0


# add locked in/locked out constraints
p1 <- problem(tfc_const_costs, cons_feat_1) %>%
       add_min_shortfall_objective(budget = 90092) %>%
       add_relative_targets(targets) %>%
       add_locked_in_constraints(pwa) %>%
       add_locked_in_constraints(existing_spa) %>%
       add_locked_out_constraints(not_state_f)



# no boundary/connectivity penalties


# adding solver

p1 <- problem(tfc_const_costs, cons_feat_1) %>%
  add_min_shortfall_objective(budget = 90092) %>%
  add_relative_targets(targets) %>%
  add_locked_in_constraints(pwa) %>%
  add_locked_in_constraints(existing_spa) %>%
  add_locked_out_constraints(not_state_f)  %>%
  add_gurobi_solver(gap = 0)

# solving with Gurobi
s1 <- solve(p1)

# Error in `solve()`:
#  ! Problem failed presolve checks.

# These checks indicate that solutions might not identify meaningful priority areas:

#  ✖ Most of the planning units do not have a single feature inside them.
# → This indicates that more features are needed.

# ℹ For more information, see `presolve_check()`.
# ℹ To ignore checks and attempt optimization anyway, use `solve(force = TRUE)`.

s1 <- solve(p1, force = TRUE)


# Gurobi Optimizer version 10.0.2 build v10.0.2rc0 (win64)
#
# CPU model: 11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz, instruction set [SSE2|AVX|AVX2|AVX512]
# Thread count: 4 physical cores, 8 logical processors, using up to 1 threads
#
# Optimize a model with 30 rows, 819919 columns and 1273808 nonzeros
# Model fingerprint: 0xf3e7b4f5
# Variable types: 29 continuous, 819890 integer (819890 binary)
# Coefficient statistics:
#   Matrix range     [1e+00, 1e+00]
# Objective range  [5e-06, 1e+00]
# Bounds range     [1e+00, 1e+00]
# RHS range        [1e+00, 2e+05]
# Found heuristic solution: objective 24.5174909
# Presolve removed 30 rows and 819919 columns
# Presolve time: 0.57s
# Presolve: All rows and columns removed
#
# Explored 0 nodes (0 simplex iterations) in 0.93 seconds (0.40 work units)
# Thread count was 1 (of 8 available processors)
#
# Solution count 2: 21.041 24.5175
#
# Optimal solution found (tolerance 0.00e+00)
# Best objective 2.104098704972e+01, best bound 2.104098704972e+01, gap 0.0000%

plot(s1)

# evaluating the solution

# calculate statistic
# cost summary
eval_cost_summary(p1, s1)

# Feature representation summary
eval_feature_representation_summary(p1, s1)

# Target coverage summary
# calculate statistics
eval_target_coverage_summary(p1, s1)
