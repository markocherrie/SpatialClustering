############### STEP 1: PRE_PROCESSING

# read in the data
library(readr)
library(sf)
dz<-read_sf("boundaries/DZ/SG_DataZoneBdry_2011/SG_DataZone_Bdry_2011.shp") 
simd<-read_csv("data/SIMD2016indicators.csv")

# pre-processing
library(dplyr)
dzsimd<- dz %>%
  left_join(simd, by= c("DataZone" = "Data_Zone")) %>%
  filter(Council_area%in%c("Glasgow City")) %>%
  mutate(SMR=as.numeric(as.character(SMR))) %>%
  mutate(SMR= ifelse(is.na(SMR), median(SMR, na.rm=TRUE), SMR)) %>%
  select(DataZone, Name, SMR)

# plot with sf
plot(dzsimd["SMR"])

### plot with tmap
library(tmap)
tmap_mode("plot")
tmap_dzsimd<-tm_shape(dzsimd) + 
  tm_fill("SMR", style = "quantile", palette = "Blues") +
  tm_borders(alpha = 0.1) +
  tm_layout(main.title = "SMR in Glasgow 2016", main.title.size = 0.7 ,
            legend.position = c("right", "bottom"), legend.title.size = 0.8)
tmap_dzsimd
tmap_mode("view")
tmap_dzsimd

# construct neighbours list from polygon list
library(sp)
library(spdep)
# convert to sp object 
dzsimd_sp <- as(dzsimd, "Spatial")
w <- poly2nb(dzsimd_sp, row.names=dzsimd_sp$DataZone)
summary(w)

# Plot the boundaries
plot(dzsimd_sp, col='white', border='gray', lwd=2)
# Get polygon centroids
xy <- coordinates(dzsimd_sp)
# Draw lines between the polygons centroids for neighbours 
# that are listed as linked in w
plot(w, xy, col='red', lwd=2, add=TRUE)


############### STEP 2: CLUSTER PROCESSING

# listw type spatial weights object
ww <-  nb2listw(w, style='B')
ww
# calculate moran's I
moran(dzsimd$SMR, ww, n=length(ww$neighbours), S0=Szero(ww))

# Calculate whether significant using monte carlo method
set.seed(1234) 
dzsimdmc_results <- moran.mc(dzsimd$SMR, ww, nsim=1000)
dzsimdmc_results
plot(dzsimdmc_results, main="", las=1)


# we need a weights matrix for this
wm <- nb2mat(w, style='B')
# row standardisation of weights matrix
rwm <- mat2listw(wm, style='W')
mat <- listw2mat(rwm)
moran.plot(dzsimd$SMR, rwm, las=1)

# Decomposition of global indicators
locm_dzsimd <- localmoran(dzsimd$SMR, ww)
summary(locm_dzsimd)
# scale the SMR
dzsimd$s_SMR <- scale(dzsimd$SMR) %>% as.vector()
# Generate the lag
dzsimd$lag_s_SMR <- lag.listw(ww, dzsimd$s_SMR)
# create a dataframe with SMR + spatial laggged SMR
x <- dzsimd$s_SMR
y <- dzsimd$lag_s_SMR 
xx <- tibble::data_frame(x,y)

############### STEP 3: CLUSTER RESULTS

# Identify significant clusters
dzsimdsp <- st_as_sf(dzsimd) %>% 
  mutate(quad_sig = ifelse(dzsimd$s_SMR > 0 & 
                             dzsimd$lag_s_SMR  > 0 & 
                             locm_dzsimd[,5] <= 0.05, 
                           "high-high",
                           ifelse(dzsimd$s_SMR <= 0 & 
                                    dzsimd$lag_s_SMR  <= 0 & 
                                    locm_dzsimd[,5] <= 0.05, 
                                  "low-low", 
                                  ifelse(dzsimd$s_SMR> 0 & 
                                           dzsimd$lag_s_SMR  <= 0 & 
                                           locm_dzsimd[,5] <= 0.05, 
                                         "high-low",
                                         ifelse(dzsimd$s_SMR <= 0 & 
                                                  dzsimd$lag_s_SMR  > 0 & 
                                                  locm_dzsimd[,5] <= 0.05,
                                                "low-high", 
                                                "non-significant")))))

# plot the significant clusters
qtm(dzsimdsp, fill="quad_sig", fill.title="LISA for SMR 2016", fill.palette = c("#DC143C","#87CEFA","#DCDCDC"))
# Summary table of clusters
table(dzsimdsp$quad_sig)

# let's get the data out so we can use later
smrclusterchange <-
  dzsimdsp %>%
  select(DataZone, quad_sig) %>%
  left_join(smr2020cluster, by="DataZone")  %>% 
  mutate(quad_sigchange = ifelse(quad_sigSMR2020 == quad_sig,"No change", 
                          ifelse(quad_sig == "non-significant" & quad_sigSMR2020 =="high-high", "Non-sig to high-high",
                          ifelse(quad_sig == "non-significant" & quad_sigSMR2020 =="low-low", "Non-sig to low-low",
                          ifelse(quad_sig == "low-low" & quad_sigSMR2020 =="non-significant", "Low-low to non-sig",
                          ifelse(quad_sig == "high-high" & quad_sigSMR2020 =="non-significant", "High-high to non-sig",
                                    "Non-classified")))))) 
  
qtm(smrclusterchange, fill="quad_sigchange", fill.title="Change in cluster 2016-2020", fill.palette = c("#ffc0cb","#32CD32","#DCDCDC", "#DC143C", "#87CEFA"))


