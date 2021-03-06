# set up the final assessment working directory
setwd("/Users/lizihao/Desktop/gis_final_data/")

# ====================================================================================
# Libraries
# ====================================================================================
library(tidyverse)
library(tmap)
library(geojsonio)
library(plotly)
library(rgdal)
library(broom)
library(mapview)
library(crosstalk)
library(sf)
library(sp)
library(spdep)
library(car)
library(fs)
library(janitor)
library(tidypredict)
library(ggplot2)
library(corrr)
library(rsample)
library(lattice)
library(caret)
library(boot)
library(spatialreg)

# ====================================================================================
# London wards information from the London datastore
Londonwards<-dir_info(here::here("statistical-gis-boundaries-london", 
                                 "ESRI"))%>%

  dplyr::filter(str_detect(path, 
                           "London_Ward_CityMerged.shp$"))%>%
  dplyr::select(path)%>%
  pull()%>%
  st_read()  

qtm(Londonwards)
# ====================================================================================
# Data cleaning
final_london <- read_csv("final_ward.csv", 
                               na = c("", "NA", "n/a"), 
                               locale = locale(encoding = 'Latin1'), 
                               col_names = TRUE)

Datatypelist <- final_london %>% 
  summarise_all(class) %>%
  pivot_longer(everything(), 
               names_to="All_variables", 
               values_to="Variable_class")

Datatypelist
#merge boundaries and data
final_lon <- Londonwards%>%
  left_join(.,
            final_london, 
            by = c("GSS_CODE" = "New code"))

#let's map our dependent variable to see if the join has worked:
tmap_mode("view")
qtm(final_lon, 
    fill = "percent_with_households_owned", 
    borders = NULL,  
    fill.palette = "Blues")

q <- qplot(x = `employment_rate`, 
           y = `percent_with_households_owned`, 
           data=final_lon)

q + stat_smooth(method="lm", se=FALSE, size=1) + 
  geom_jitter()

#run the linear regression model and store its outputs in an object called model1
Regressiondata<- final_lon%>%
  clean_names()%>%
  dplyr::select(general_fertility_rate,
                percent_with_households_owned,
                population_density_persons_per_sq_km,
                employment_rate,
                crime_rate,
                average_public_transport_accessibility_score,
                average_gcse_capped_point_scores)

# model 1
model1 <- Regressiondata %>%
  lm(percent_with_households_owned ~
       employment_rate +
       general_fertility_rate +
       population_density_persons_per_sq_km +
       crime_rate +
       average_public_transport_accessibility_score +
       average_gcse_capped_point_scores,

     data=.)
# summary model 1, it might occupy a large area
summary(model1)
# Residual standard error: 9.184 on 619 degrees of freedom
# Multiple R-squared:  0.7626,	Adjusted R-squared:  0.7603 
# F-statistic: 331.5 on 6 and 619 DF,  p-value: < 2.2e-16
tidy(model1)
# term                                          estimate std.error statistic  p.value
# <chr>                                            <dbl>     <dbl>     <dbl>    <dbl>
# 1 (Intercept)                                  -43.2      7.45        -5.81  1.02e- 8
# 2 employment_rate                                0.740    0.0701      10.5   4.96e-24
# 3 general_fertility_rate                        -0.00820  0.0283      -0.290 7.72e- 1
# 4 population_density_persons_per_sq_km          -0.00102  0.000118    -8.63  5.00e-17
# 5 crime_rate                                    -0.0205   0.00603     -3.40  7.30e- 4
# 6 average_public_transport_accessibility_score  -5.60     0.476      -11.8   6.27e-29
# 7 average_gcse_capped_point_scores               0.224    0.0196      11.4   1.26e-27

glance(model1)
# r.squared adj.r.squared sigma statistic   p.value    df logLik   AIC   BIC deviance df.residual  nobs
# <dbl>         <dbl> <dbl>     <dbl>     <dbl> <dbl>  <dbl> <dbl> <dbl>    <dbl>       <int> <int>
# 0.763         0.760  9.18      331. 1.37e-189     6 -2273. 4562. 4597.   52208.         619   626

# some useful functions for model_1
coefficients(model1)
confint(model1, level=0.95)
residuals(model1) # residuals
anova(model1) # anova table
vcov(model1) # covariance matrix for model parameters
influence(model1) # regression diagnostics

# ====================================================================================
# Bootstrap resampling for model1
Bootstrapdata<- final_lon%>%
  clean_names()%>%
  dplyr::select(general_fertility_rate,
                percent_with_households_owned,
                population_density_persons_per_sq_km,
                employment_rate,
                crime_rate,
                average_public_transport_accessibility_score,
                average_gcse_capped_point_scores)
# library(lattice)
# library(caret)
# library(boot)
set.seed(99)
# employment_rate
mr <-st_drop_geometry(Bootstrapdata) %>%
  bootstraps(times = 1000, apparent = TRUE)

slice_tail(mr, n=5)
# splits            id           
# <list>            <chr>        
# 1 <split [626/229]> Bootstrap0997
# 2 <split [626/222]> Bootstrap0998
# 3 <split [626/217]> Bootstrap0999
# 4 <split [626/222]> Bootstrap1000
# 5 <split [626/626]> Apparent  

mr_model <- mr %>%
  mutate(
    #column name is model that contains...
    model = map(splits, ~ lm(percent_with_households_owned ~ employment_rate, 
                             data = .)))

#the first model results
mr_model$model[[1]]
# Coefficients:
#   (Intercept)  employment_rate  
# -62.948            1.637   
mr_model_tidy <- mr_model %>%
  mutate(
    coef_info = map(model, tidy))
mr_coef <- mr_model_tidy %>%
  unnest(coef_info)
mr_coef
# splits            id            model  term            estimate std.error statistic  p.value
# <list>            <chr>         <list> <chr>              <dbl>     <dbl>     <dbl>    <dbl>
#   1 <split [626/246]> Bootstrap0001 <lm>   (Intercept)       -62.9     6.15      -10.2  7.86e-23
# 2 <split [626/246]> Bootstrap0001 <lm>   employment_rate     1.64    0.0878     18.6  5.24e-62
# 3 <split [626/233]> Bootstrap0002 <lm>   (Intercept)       -69.7     7.07       -9.85 2.22e-21
# 4 <split [626/233]> Bootstrap0002 <lm>   employment_rate     1.72    0.101      17.1  7.22e-54
# 5 <split [626/248]> Bootstrap0003 <lm>   (Intercept)       -68.5     6.38      -10.7  7.65e-25
# 6 <split [626/248]> Bootstrap0003 <lm>   employment_rate     1.72    0.0910     18.9  1.51e-63
# 7 <split [626/229]> Bootstrap0004 <lm>   (Intercept)       -56.8     6.37       -8.91 5.58e-18
# 8 <split [626/229]> Bootstrap0004 <lm>   employment_rate     1.53    0.0916     16.7  3.87e-52
# 9 <split [626/221]> Bootstrap0005 <lm>   (Intercept)       -52.1     6.77       -7.71 5.15e-14
# 10 <split [626/221]> Bootstrap0005 <lm>   employment_rate     1.46    0.0970     15.1  4.46e-44
# # … with 1,992 more rows
coef <- mr_coef %>% 
  filter(term == "employment_rate")
coef
# splits            id            model  term            estimate std.error statistic  p.value
# <list>            <chr>         <list> <chr>              <dbl>     <dbl>     <dbl>    <dbl>
#   1 <split [626/246]> Bootstrap0001 <lm>   employment_rate     1.64    0.0878      18.6 5.24e-62
# 2 <split [626/233]> Bootstrap0002 <lm>   employment_rate     1.72    0.101       17.1 7.22e-54
# 3 <split [626/248]> Bootstrap0003 <lm>   employment_rate     1.72    0.0910      18.9 1.51e-63
# 4 <split [626/229]> Bootstrap0004 <lm>   employment_rate     1.53    0.0916      16.7 3.87e-52
# 5 <split [626/221]> Bootstrap0005 <lm>   employment_rate     1.46    0.0970      15.1 4.46e-44
# 6 <split [626/231]> Bootstrap0006 <lm>   employment_rate     1.49    0.0911      16.4 2.67e-50
# 7 <split [626/224]> Bootstrap0007 <lm>   employment_rate     1.65    0.0969      17.0 1.05e-53
# 8 <split [626/240]> Bootstrap0008 <lm>   employment_rate     1.65    0.0957      17.2 1.07e-54
# 9 <split [626/248]> Bootstrap0009 <lm>   employment_rate     1.48    0.0979      15.1 4.27e-44
# 10 <split [626/228]> Bootstrap0010 <lm>   employment_rate     1.63    0.0921      17.7 2.67e-57
# # … with 991 more rows
coef %>%
  ggplot(aes(x=estimate)) +
  geom_histogram(position="identity", 
                 alpha=0.5, 
                 bins=15, 
                 fill="lightblue2", col="lightblue3")+
  geom_vline(aes(xintercept=mean(estimate)),
             color="blue",
             linetype="dashed")+
  labs(title="Bootstrap resample estimates",
       x="Coefficient estimates",
       y="Frequency")+
  theme_classic()+
  theme(plot.title = element_text(hjust = 0.5))
#seting the apparent argument to true earlier on and the requirement of int_pctl()
int_pctl(mr_model_tidy, coef_info, alpha = 0.05)
# term            .lower .estimate .upper .alpha .method   
# <chr>            <dbl>     <dbl>  <dbl>  <dbl> <chr>     
#   1 (Intercept)     -73.3     -60.5  -48.8    0.05 percentile
# 2 employment_rate   1.41      1.58   1.77   0.05 percentile
mr_aug <- mr_model_tidy %>%
  #sample_n(5) %>%
  mutate(augmented = map(model, augment))%>%
  unnest(augmented)
length(final_lon$`percent_with_households_owned`)
# [1]626
boot1<-filter(mr_aug,id=="Bootstrap0001")

bootlength1 <- boot1 %>%
  dplyr::select(percent_with_households_owned)%>%
  pull()%>%
  length()

ggplot(mr_aug, aes(employment_rate,
                    percent_with_households_owned))+
  
  geom_line(aes(y = .fitted, group = id), alpha = .2, col = "cyan3") +  
  
  geom_point(data=filter(mr_aug,id=="Apparent"))+
  #add some labels to x and y
  labs(x="employment_rate (%)",
       y="percent_with_households_owned")

# It is also necessary to bootstrap resample for the other five independent variables
# ====================================================================================
#Assumptions Underpinning Linear Regression
#data transformtion
final_lon <- final_lon %>%
  clean_names()

#checking the distribution of these variables first
ggplot(final_lon, aes(x=percent_with_households_owned)) + 
  geom_histogram(stat="count")

#percent_with_households_owned distribution
ggplot(final_lon, aes(x=percent_with_households_owned)) + 
  geom_histogram(aes(y = ..density..),
                 binwidth = 5) + 
  geom_density(colour="red", 
               size=1, 
               adjust=1)

#general_fertility_rate distribution
ggplot(final_lon, aes(x=general_fertility_rate)) + 
  geom_histogram(aes(y = ..density..),
                 binwidth = 5) + 
  geom_density(colour="red", 
               size=1, 
               adjust=1)

#population_density_persons_per_sq_km distribution
ggplot(final_lon, aes(x=population_density_persons_per_sq_km)) + 
  geom_histogram(aes(y = ..density..),
                 binwidth = 2000) + 
  geom_density(colour="red", 
               size=1, 
               adjust=1)

#employment_rate distribution
ggplot(final_lon, aes(x=employment_rate)) + 
  geom_histogram(aes(y = ..density..),
                 binwidth = 3) + 
  geom_density(colour="red", 
               size=1, 
               adjust=1)

#crime_rate distribution
ggplot(final_lon, aes(x=crime_rate)) + 
  geom_histogram(aes(y = ..density..),
                 binwidth = 30) + 
  geom_density(colour="red", 
               size=1, 
               adjust=1)
#crime rate is a not normal and/or positively ‘skewed’ distribution
qplot(x = crime_rate, 
      y = percent_with_households_owned, 
      data=final_lon)
#transforming crime rate
ggplot(final_lon, aes(x=log(crime_rate))) + 
  geom_histogram()
#symbox() function in the library(car)
symbox(~crime_rate, 
       final_lon, 
       na.rm=T,
       powers=seq(-3,3,by=.5))

qplot(x = (crime_rate)^-1, 
      y = percent_with_households_owned,
      data=final_lon)

#average_public_transport_accessibility_score distribution
ggplot(final_lon, aes(x=average_public_transport_accessibility_score)) + 
  geom_histogram(aes(y = ..density..),
                 binwidth = 0.5) + 
  geom_density(colour="red", 
               size=1, 
               adjust=1)
#transforming average_public_transport_accessibility_score
ggplot(final_lon, aes(x=log(average_public_transport_accessibility_score))) + 
  geom_histogram()
symbox(~average_public_transport_accessibility_score, 
       final_lon, 
       na.rm=T,
       powers=seq(-3,3,by=.5))

qplot(x = (average_public_transport_accessibility_score)^-1, 
      y = percent_with_households_owned,
      data=final_lon)

#average_gcse_capped_point_scores distribution
ggplot(final_lon, aes(x=average_gcse_capped_point_scores)) + 
  geom_histogram(aes(y = ..density..),
                 binwidth = 5) + 
  geom_density(colour="red", 
               size=1, 
               adjust=1)

# ====================================================================================
#testing the residuals of model_1
model_data <- model1 %>%
  augment(., Regressiondata)
#plot the residuals
model_data%>%
  dplyr::select(.resid)%>%
  pull()%>%
  qplot()+ 
  geom_histogram()

# Model2
# ====================================================================================
#testing the non-multicolinearity in the independent varibles
Regressiondata_2<- final_lon%>%
  clean_names()%>%
  dplyr::select(percent_with_households_owned,
                general_fertility_rate,
                population_density_persons_per_sq_km,
                employment_rate,
                crime_rate,
                average_public_transport_accessibility_score,
                average_gcse_capped_point_scores)

model2 <- lm(percent_with_households_owned ~ 
               general_fertility_rate + 
               population_density_persons_per_sq_km +
               employment_rate +
               log(crime_rate) +
               log(average_public_transport_accessibility_score) +
               average_gcse_capped_point_scores,
             
            data = Regressiondata_2)

#show the summary of those outputs
tidy(model2)
# term                                                estimate std.error statistic  p.value
# <chr>                                                  <dbl>     <dbl>     <dbl>    <dbl>
#   1 (Intercept)                                         6.90      9.10         0.758 4.49e- 1
# 2 general_fertility_rate                              0.0182    0.0252       0.725 4.69e- 1
# 3 population_density_persons_per_sq_km               -0.000969  0.000110    -8.82  1.20e-17
# 4 employment_rate                                     0.684     0.0660      10.4   2.77e-23
# 5 log(crime_rate)                                    -8.47      1.09        -7.80  2.57e-14
# 6 log(average_public_transport_accessibility_score) -18.5       1.88        -9.85  2.33e-21
# 7 average_gcse_capped_point_scores                    0.189     0.0184      10.2   7.26e-23

glance(model2)
# r.squared adj.r.squared sigma statistic   p.value    df logLik   AIC   BIC deviance df.residual  nobs
# <dbl>         <dbl> <dbl>     <dbl>     <dbl> <dbl>  <dbl> <dbl> <dbl>    <dbl>       <int> <int>
# 0.798         0.796  8.47      408. 2.08e-211     6 -2222. 4460. 4495.   44373.         619   626
# ====================================================================================
#testing the residuals of model_2
modeldata_2 <- model2 %>%
  augment(., Regressiondata_2)

modeldata_2%>%
  dplyr::select(.resid)%>%
  pull()%>%
  qplot()+ 
  geom_histogram()

# ====================================================================================
# also add them to the shapelayer
final_lon <- final_lon %>%
  mutate(model2resids = residuals(model2))

Correlation_all<- final_lon %>%
  st_drop_geometry()%>%
  dplyr::select(percent_with_households_owned,
                general_fertility_rate,
                population_density_persons_per_sq_km,
                employment_rate,
                crime_rate,
                average_public_transport_accessibility_score,
                average_gcse_capped_point_scores) %>%
  
  mutate(
         crime_rate =log(crime_rate),
         average_public_transport_accessibility_score = log(average_public_transport_accessibility_score)) %>%
  correlate() %>%
  # just focus on GCSE and house prices
  focus(-population_density_persons_per_sq_km, mirror = TRUE)

rplot(Correlation_all)
# ====================================================================================
#testing the variance inflation factor(VIF)
vif(model2)
# general_fertility_rate                            population_density_persons_per_sq_km 
# 1.277735                                          2.493486 
# employment_rate                                   log(crime_rate) 
# 1.597192                                          2.261215 
# log(average_public_transport_accessibility_score) average_gcse_capped_point_scores 
# 3.885337                                          1.379359 
position <- c(10:17)

Correlation_all<- final_lon %>%
  st_drop_geometry()%>%
  dplyr::select(position)%>%
  correlate()

rplot(Correlation_all)

# ====================================================================================
#testing the homoscedasticity
#Homoscedasticity means that the errors/residuals in the model exhibit constant / homogenous variance
#print the model diagnositcs. 
par(mfrow=c(2,2))    #plot to 2 by 2 array
plot(model2)  #the 4 figures is important 
# ====================================================================================
#testing the independence of errors
#Durbin-Watson test
dw <- durbinWatsonTest(model2)
tidy(dw)
# statistic p.value autocorrelation method             alternative
# <dbl>   <dbl>           <dbl> <chr>              <chr>      
# 1.30       0           0.350 Durbin-Watson Test two.sided  
coordsW <- final_lon%>%
  st_centroid()%>%
  st_geometry()
plot(coordsW)

LWard_nb <- final_lon %>%
  poly2nb(., queen=T)

#or nearest neighbours
knn_wards <-coordsW %>%
  knearneigh(., k=4)
LWard_knn <- knn_wards %>%
  knn2nb()

#plot them
plot(LWard_nb, st_geometry(coordsW), col="red")
plot(LWard_knn, st_geometry(coordsW), col="blue")

plot(final_lon)

Lward.queens_weight <- LWard_nb %>%
  nb2listw(., style="C")
Lward.knn_4_weight <- LWard_knn %>%
  nb2listw(., style="C")
Queen <- final_lon %>%
  st_drop_geometry()%>%
  dplyr::select(model2resids)%>%
  pull()%>%
  moran.test(., Lward.queens_weight)%>%
  tidy()

Nearest_neighbour <- final_lon %>%
  st_drop_geometry()%>%
  dplyr::select(model2resids)%>%
  pull()%>%
  moran.test(., Lward.knn_4_weight)%>%
  tidy()

Queen
# estimate1 estimate2 estimate3 statistic  p.value method                           alternative
# <dbl>     <dbl>     <dbl>     <dbl>    <dbl> <chr>                            <chr>      
# 0.476   -0.0016  0.000534      20.7 2.82e-95 Moran I test under randomisation greater   
Nearest_neighbour
# estimate1 estimate2 estimate3 statistic  p.value method                           alternative
# <dbl>     <dbl>     <dbl>     <dbl>    <dbl> <chr>                            <chr>      
# 0.472   -0.0016  0.000720      17.7 4.11e-70 Moran I test under randomisation greater    

# ====================================================================================
#Lagrange multipliers testing

final_lon$res_model2 <- residuals(model2)

final_lon$fitted_model2 <- fitted(model2)

final_lon$sd_breaks <- scale(final_lon$res_model2)[,1] 

summary(final_lon$sd_breaks)
# Min.  1st Qu.   Median     Mean  3rd Qu.     Max. 
# -3.71216 -0.61211  0.01493  0.00000  0.69752  2.50496 
my_breaks <- c(-14,-3,-2,-1,1,2,3,14)

tm_shape(final_lon) + 
  tm_fill("sd_breaks", title = "Residuals", style = "fixed", breaks = my_breaks, palette = "-RdBu") +
  tm_borders(alpha = 0.1) +
  tm_layout(main.title = "Residuals", main.title.size = 0.7 ,
            legend.position = c("right", "bottom"), legend.title.size = 0.8)

final_sp <- as(final_lon, "Spatial")
#Then we create a list of neighbours using the Queen criteria
w <- poly2nb(final_sp, row.names=final_sp$FIPSNO)
summary(w)
# Neighbour list object:
# Number of regions: 626 
# Number of nonzero links: 3704 
# Percentage nonzero weights: 0.945197 
# Average number of links: 5.916933 
# Link number distribution:
#   
# 1   2   3   4   5   6   7   8   9  10  11  12 
# 1   4  15  72 160 178 118  52  17   4   1   4 
# 1 least connected region:
#   1 with 1 link
# 4 most connected regions:
#   135 481 625 626 with 12 links

wm <- nb2mat(w, style='B')
rwm <- mat2listw(wm, style='W')

lm.morantest(model2, rwm, alternative="two.sided")

# Global Moran I for regression residuals
# 
# data:  
#   model: lm(formula = percent_with_households_owned ~ general_fertility_rate +
#               population_density_persons_per_sq_km + employment_rate + log(crime_rate) +
#               log(average_public_transport_accessibility_score) + average_gcse_capped_point_scores, data =
#               Regressiondata_2)
# weights: rwm
# 
# Moran I statistic standard deviate = 20.463, p-value < 2.2e-16
# alternative hypothesis: two.sided
# sample estimates:
# Observed Moran I      Expectation         Variance 
# 0.4726919149    -0.0056717852     0.0005464598 

ggplot(final_lon, aes(x = res_model2)) + 
  geom_density() 

lm.LMtests(model2, rwm, test = c("LMerr","LMlag","RLMerr","RLMlag","SARMA"))
# Lagrange multiplier diagnostics for spatial dependence
# 
# data:  
#   model: lm(formula = percent_with_households_owned ~ general_fertility_rate +
#               population_density_persons_per_sq_km + employment_rate + log(crime_rate) +
#               log(average_public_transport_accessibility_score) + average_gcse_capped_point_scores, data =
#               Regressiondata_2)
# weights: rwm
# 
# LMerr = 397.66, df = 1, p-value < 2.2e-16
#
# Lagrange multiplier diagnostics for spatial dependence
# 
# data:  
#   model: lm(formula = percent_with_households_owned ~ general_fertility_rate +
#               population_density_persons_per_sq_km + employment_rate + log(crime_rate) +
#               log(average_public_transport_accessibility_score) + average_gcse_capped_point_scores, data =
#               Regressiondata_2)
# weights: rwm
# 
# LMlag = 273.39, df = 1, p-value < 2.2e-16
# 
# 
# Lagrange multiplier diagnostics for spatial dependence
# 
# data:  
#   model: lm(formula = percent_with_households_owned ~ general_fertility_rate +
#               population_density_persons_per_sq_km + employment_rate + log(crime_rate) +
#               log(average_public_transport_accessibility_score) + average_gcse_capped_point_scores, data =
#               Regressiondata_2)
# weights: rwm
# 
# RLMerr = 156.35, df = 1, p-value < 2.2e-16
# 
# 
# Lagrange multiplier diagnostics for spatial dependence
# 
# data:  
#   model: lm(formula = percent_with_households_owned ~ general_fertility_rate +
#               population_density_persons_per_sq_km + employment_rate + log(crime_rate) +
#               log(average_public_transport_accessibility_score) + average_gcse_capped_point_scores, data =
#               Regressiondata_2)
# weights: rwm
# 
# RLMlag = 32.076, df = 1, p-value = 1.482e-08
# 
# 
# Lagrange multiplier diagnostics for spatial dependence
# 
# data:  
#   model: lm(formula = percent_with_households_owned ~ general_fertility_rate +
#               population_density_persons_per_sq_km + employment_rate + log(crime_rate) +
#               log(average_public_transport_accessibility_score) + average_gcse_capped_point_scores, data =
#               Regressiondata_2)
# weights: rwm
# 
# SARMA = 429.74, df = 2, p-value < 2.2e-16
# ====================================================================================
#fit and interpret a spatially lagged model
model2_lag <- lagsarlm(percent_with_households_owned ~ 
                         general_fertility_rate + 
                         population_density_persons_per_sq_km +
                         employment_rate +
                         log(crime_rate) +
                         log(average_public_transport_accessibility_score) +
                         average_gcse_capped_point_scores,
                       
                       data=final_lon, rwm)

glance(model2_lag)
# r.squared   AIC   BIC deviance logLik  nobs
# <dbl> <dbl> <dbl>    <dbl>  <dbl> <int>
# 0.872 4210. 4250.   28166. -2096.   626
summary(model2_lag)
# Call:lagsarlm(formula = percent_with_households_owned ~ general_fertility_rate + 
#                 population_density_persons_per_sq_km + employment_rate + 
#                 log(crime_rate) + log(average_public_transport_accessibility_score) + 
#                 average_gcse_capped_point_scores, data = final_lon, listw = rwm)
# 
# Residuals:
#   Min        1Q      Median        3Q       Max 
# -18.89361  -4.59418   0.08083   4.27835  19.47971 
# 
# Type: lag 
# Coefficients: (asymptotic standard errors) 
# Estimate  Std. Error z value  Pr(>|z|)
# (Intercept)                                       -1.5655e+01  7.2410e+00 -2.1619   0.03062
# general_fertility_rate                            -8.8260e-03  2.0024e-02 -0.4408   0.65938
# population_density_persons_per_sq_km              -4.3825e-04  9.1895e-05 -4.7690 1.851e-06
# employment_rate                                    4.8675e-01  5.6014e-02  8.6899 < 2.2e-16
# log(crime_rate)                                   -5.6714e+00  8.8185e-01 -6.4312 1.266e-10
# log(average_public_transport_accessibility_score) -1.0252e+01  1.5493e+00 -6.6174 3.657e-11
# average_gcse_capped_point_scores                   1.4592e-01  1.4816e-02  9.8490 < 2.2e-16
# 
# Rho: 0.50469, LR test value: 252.28, p-value: < 2.22e-16
# Asymptotic standard error: 0.028907
# z-value: 17.459, p-value: < 2.22e-16
# Wald statistic: 304.81, p-value: < 2.22e-16
# 
# Log likelihood: -2095.82 for lag model
# ML residual variance (sigma squared): 44.994, (sigma: 6.7078)
# Number of observations: 626 
# Number of parameters estimated: 9 
# AIC: 4209.6, (AIC for lm: 4459.9)
# LM test for residual autocorrelation
# test value: 73.288, p-value: < 2.22e-16
tidy(model2_lag)
# term                                              estimate std.error statistic     p.value
# <chr>                                                <dbl>     <dbl>     <dbl>       <dbl>
#   1 rho                                                  0.543    0.0272     20.0  0          
# 2 (Intercept)                                        -29.3      6.02       -4.86 0.00000117 
# 3 employment_rate                                      0.541    0.0541      9.99 0          
# 4 log(crime_rate)                                     -4.03     0.820      -4.92 0.000000857
# 5 log(average_public_transport_accessibility_score)  -14.3      1.27      -11.3  0          
# 6 average_gcse_capped_point_scores                     0.152    0.0148     10.2  0      

W <- as(rwm, "CsparseMatrix")
trMC <- trW(W, type="MC")
im<-impacts(model2_lag, tr=trMC, R=100)
sums<-summary(im,  zstats=T)
#To print the coefficients
data.frame(sums$res)
# direct      indirect         total
# 1 -9.326886e-03 -0.0084924092 -1.781929e-02
# 2 -4.631194e-04 -0.0004216841 -8.848036e-04
# 3  5.143720e-01  0.4683511660  9.827232e-01
# 4 -5.993196e+00 -5.4569845970 -1.145018e+01
# 5 -1.083424e+01 -9.8649013732 -2.069914e+01
# 6  1.542051e-01  0.1404084017  2.946135e-01

data.frame(sums$pzmat)
# Direct     Indirect        Total
# general_fertility_rate                            6.329411e-01 6.312095e-01 6.314993e-01
# population_density_persons_per_sq_km              6.034419e-06 1.410273e-06 1.319145e-06
# employment_rate                                   0.000000e+00 0.000000e+00 0.000000e+00
# log(crime_rate)                                   8.734058e-11 7.211386e-09 8.551027e-11
# log(average_public_transport_accessibility_score) 5.040635e-12 2.317422e-09 1.070299e-11
# average_gcse_capped_point_scores                  0.000000e+00 1.328693e-11 0.000000e+00
# ====================================================================================
model2_OLS <- lm(percent_with_households_owned ~ 
                   general_fertility_rate + 
                   population_density_persons_per_sq_km +
                   employment_rate +
                   log(crime_rate) +
                   log(average_public_transport_accessibility_score) +
                   average_gcse_capped_point_scores
                 
                 , data=Regressiondata_2)

summary(model2_OLS)
# Call:
#   lm(formula = percent_with_households_owned ~ general_fertility_rate + 
#        population_density_persons_per_sq_km + employment_rate + 
#        log(crime_rate) + log(average_public_transport_accessibility_score) + 
#        average_gcse_capped_point_scores, data = Regressiondata_2)
# 
# Residuals:
#   Min       1Q   Median       3Q      Max 
# -31.2784  -5.1576   0.1258   5.8772  21.1067 
# 
# Coefficients:
# Estimate Std. Error t value Pr(>|t|)    
# (Intercept)                                        6.897e+00  9.096e+00   0.758    0.449    
# general_fertility_rate                             1.824e-02  2.517e-02   0.725    0.469    
# population_density_persons_per_sq_km              -9.686e-04  1.099e-04  -8.815  < 2e-16 ***
# employment_rate                                    6.835e-01  6.601e-02  10.356  < 2e-16 ***
# log(crime_rate)                                   -8.473e+00  1.086e+00  -7.804 2.57e-14 ***
# log(average_public_transport_accessibility_score) -1.852e+01  1.881e+00  -9.849  < 2e-16 ***
# average_gcse_capped_point_scores                   1.888e-01  1.842e-02  10.247  < 2e-16 ***
#   ---
# Signif. codes:  0 ‘***’ 0.001 ‘**’ 0.01 ‘*’ 0.05 ‘.’ 0.1 ‘ ’ 1
# 
# Residual standard error: 8.467 on 619 degrees of freedom
# Multiple R-squared:  0.7983,	Adjusted R-squared:  0.7963 
# F-statistic: 408.2 on 6 and 619 DF,  p-value: < 2.2e-16


#END
# ====================================================================================
