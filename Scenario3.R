# to different area targets based on the ownership type:
# eligible forest: 39254
# state forest: 21662

library(prioritizr)
library(sf)
library(terra)
library(vegan)
library(cluster)
library(raster)
library(gurobi)


# load planning unit data
tfc_costs <- rast("C:/Users/Fabio Castelli/OneDrive - Alma Mater Studiorum Università di Bologna/Desktop/NRW_Data/u2018_clc2018_v2020_20u1_geoPackage/total_forest_cover_25832.tif")

# creating a new raster with constant costs
tfc_const_costs <- (tfc_costs*0) + 1

# loading conservation features
existing_spa <- rast("C:/Users/Fabio Castelli/OneDrive - Alma Mater Studiorum Università di Bologna/Desktop/NRW_Data/Forest strictly protected/Forest_strictly_protected_25832_revised.tif")
N2000 <- rast("C:/Users/Fabio Castelli/OneDrive - Alma Mater Studiorum Università di Bologna/Desktop/NRW_Data/Occurrence of FFH habitat types in North Rhine-Westphalia/Habitat_directive_FFH_25832.tif")
fht <- rast("C:/Users/Fabio Castelli/OneDrive - Alma Mater Studiorum Università di Bologna/Desktop/NRW_Data/Habitat_types_AnnexI/Dataset_from_Lanuv/forest_habitat_types_reclas_25832.tif") 
state_f <- rast("C:/Users/Fabio Castelli/OneDrive - Alma Mater Studiorum Università di Bologna/Desktop/NRW_Data/Public forest/State_forest_25832.tif")
eligible_f <- rast("C:/Users/Fabio Castelli/OneDrive - Alma Mater Studiorum Università di Bologna/Desktop/NRW_Data/Eligible Forest + federal forest/Eligible_forest-Federal_forest_25832.tif")

# create a binary stack for fht raster
bstacked_fht <- binary_stack(fht) 

# set names to keep track of all the different fht
names(bstacked_fht) <- paste0("class_", seq_len(nlyr(bstacked_fht)))

# remove layers with only zeros
bstacked_fht <- bstacked_fht[[which(global(bstacked_fht, "max", na.rm = TRUE)[[1]] > 0.5)]]

# I want to prioritize the cells corresponding to highly damaged forest --> cells with highly damaged forest should have higher values because
# we expect private forest owners to prioritize those stands when they want to set aside 5% of their holdings to get the incentives

# loading the high vitality decreased layer
vit_dec <- rast("C:/Users/Fabio Castelli/OneDrive - Alma Mater Studiorum Università di Bologna/Desktop/NRW_Data/Vitality Decrease/vitality_highly_decreased_25832.tif")

# setting value 1 for all the cells
reclass_matrix_vt_3 <- matrix(c(0.25, 1), ncol = 2, byrow = TRUE)
vit_dec_3 <-  classify(vit_dec, reclass_matrix_vt_3)


# I need to change eligible_f layer values in this way: when overlap with vit_dec-> value 1, when it doesn't overlap-> 0.25

# first, update eligible_f values as default 0.25 setting value 0.25 for all the cells
reclass_matrix_ef_3 <- matrix(c(1, 0.25), ncol = 2, byrow = TRUE)
eligible_f <-  classify(eligible_f, reclass_matrix_ef_3)

# then, trying to change the values according to vit_dec this way: 

modified_eligible_f <-terra::mask(eligible_f, mask = (eligible_f > 0.2) & (vit_dec == 1), maskvalues = 1, updatevalue = 1)


# creating the conservation feature object
cons_feat_3 <- c(bstacked_fht, N2000, existing_spa, state_f, modified_eligible_f)

#targets3
targets3 <- c(
  rep(0.3, nlyr(modified_bstacked_fht)), ## >= 30% coverage of each forest type
  0.3,                                   ## >= 30% coverage of N2000
  0,                                     ##  >= 0% coverage of existing_spa
  0,                                     ## >= 0% coverage of state_f
  0                                      ## eligible_f
)


# setting the problem 
p3 <-
  problem(tfc_const_costs, cons_feat_3) %>%
  add_min_shortfall_objective(budget = 60486) %>%
  add_relative_targets(targets3) %>%
  add_linear_constraints(
    threshold = 21662,
    sense = "<=",
    data = state_f
  ) %>%
  add_linear_constraints(
    threshold = 39254,
    sense = "<=",
    data = modified_eligible_f
  ) %>%
  add_locked_out_constraints(existing_spa) %>%
  add_gurobi_solver(gap = 0)


s3 <- solve(p3, force = TRUE) #

plot(s3)

# evaluating the solution

# calculate statistic 
# cost summary
eval_cost_summary(p3, s3)

# Feature representation summary
print(eval_feature_representation_summary(p3, s3), n=30)

# Target coverage summary
# calculate statistics
print(eval_target_coverage_summary(p3, s3), n=30)
