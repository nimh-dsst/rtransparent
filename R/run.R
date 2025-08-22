#!/usr/bin/env Rscript

library(magrittr)
source("xml_utils.R")
source("rt_coi_pmc.R")
source("rt_all_pmc.R")
source("rt_register_pmc.R")
source("rt_fund_pmc.R")
source("utils.R")

args <- commandArgs(trailingOnly = T) # Take inputs from argc
vectorized_rt <- Vectorize(rt_all_pmc, vectorize.args=c("filename"), SIMPLIFY=F) # remap the rt_all_pmc function to run over vector

out <- vectorized_rt(args) %>% Filter(function(x) length(x) == 116, .) %>% do.call(rbind, .) # run & bind into a big tibble

outDir <- Sys.getenv("R_OUTDIR", "~")

# print
write.table(out, file.path(outDir, "out.csv"), sep=",", col.names=F, row.names=F)
write.table(t(names(out)), file.path(outDir, "out.names.csv"), sep=",", col.names=F, row.names=F)
