# ==============================================================================
# Trend analysis of historical CBC observations of Marbled Murrelet in Seattle
# September 24, 2025
# Joshua Morris, Conservation Director, Birds Connect Seattle
# ==============================================================================

# Historical CBC data available at christmasbirdcount.org
# Seattle area count circle id = "WASE"


# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================

# clear environment
rm(list = ls())

# load required packages
if (!require("pacman")) install.packages("pacman")
pacman::p_load(tidyverse,
               glmmTMB,
               DHARMa)

# ==============================================================================
# LOAD THEME AND DATA
# ==============================================================================

# custom theme for bcs brand / style
source("custom_theme/theme_bcs.R") 

# load historical cbc MAMU data
d <- read.csv("data/mamu_cbc.csv")

# explore data
summary(d)
str(d)
head(d)
view(d)

ggplot(d, aes(x = year, y = mamu.count)) + geom_point() + theme_minimal()

# prepare data for modeling
d$syear <- as.numeric(scale(d$year)) # z-standardized year term
d$sph <- as.numeric(scale(d$est.party.hours)) # z-standardized term for search effort

# prepare useful variables
year_sd <- sd(d$year)
year_mean <- mean(d$year)

# ==============================================================================
# MODEL SELECTION
# ==============================================================================

# Test models
mod.null <- glmmTMB(mamu.count ~ 1, data = d, family = poisson)
mod.1 <- glmmTMB(mamu.count ~ syear, data = d, family = poisson)
mod.2 <- glmmTMB(mamu.count ~ syear + sph, data = d, family = poisson)

summary(mod.null)
summary(mod.1) # syear highly significant
summary(mod.2) # syear highly significant, sph not significant

AIC(mod.null, mod.1, mod.2) # most support for model 1

# Check dispersion and zero inflaction
res <- simulateResiduals(mod.1)
plot(res)
testDispersion(res) # Overdispersion an issue
testZeroInflation(res) # Zero inflation also an issue

# Try negative binomial models
mod.nb1 <- glmmTMB(mamu.count ~ syear, data = d, family = nbinom1)
mod.nb2 <- glmmTMB(mamu.count ~ syear, data = d, family = nbinom2)

AIC(mod.1, mod.nb1, mod.nb2) # Most support for mod.nb2

res <- simulateResiduals(mod.nb2)
plot(res)
testDispersion(res) # overdispersion not an issue with the nb2 distribution
testZeroInflation(res) # zero inflation not an issue with nb2 distribution

# Select mod.nb2 for count trend modeling
beta <- summary(mod.nb2)$coefficients$cond["syear", "Estimate"]
se <- summary(mod.nb2)$coefficients$cond["syear", "Std. Error"]

# backtransform from log scale and express as annual % change
est <- (exp(beta / year_sd) - 1) * 100 # point estimate
upp <- (exp((beta + 1.96 * se) / year_sd) - 1) * 100
low <- (exp((beta - 1.96 * se) / year_sd) - 1) * 100

# ==============================================================================
# VISUALIZE RESULTS
# ==============================================================================

# new data set for predictions
new_data <- expand.grid(
  syear1 = seq(min(d.join$syear), max(d.join$syear) + (1 / year_sd), length.out = 100)
)

new_data$year <- round(new_data$syear1 * year_sd + mean(d$year), 0)

new_data <- left_join(new_data, d.join, join_by("year" == "year")) %>% select(-syear) %>% rename(syear = syear1)


preds <- predict(mod.nb2, newdata = new_data, type = "link", se.fit = TRUE)

new_data$fit <- preds$fit
new_data$se <- preds$se.fit
new_data$upper <- preds$fit + 1.96 * new_data$se
new_data$lower <- preds$fit - 1.96 * new_data$se
new_data$bkt_est <- exp(new_data$fit)
new_data$bkt_upper <- exp(new_data$upper)
new_data$bkt_lower <- exp(new_data$lower)

summary(new_data)


# Calculate a scaling factor for chart
scale_factor <- max(new_data$mamu.count, na.rm = TRUE) / max(new_data$observer.count, na.rm = TRUE)

chart <- ggplot(new_data) + 
  # observer count line scaled to fit the primary y-axis
  geom_line(data = d, aes(x = year, y = observer.count * scale_factor, 
                          color = "Number of Observers"), linetype = "solid") +
  
  # count model estimate 95% CI
  geom_ribbon(aes(x = (syear*year_sd+mean(d.join$year)), ymin = bkt_lower, ymax = bkt_upper, 
                  fill = "95% Confidence Interval"), alpha = 0.2) +
  
  # count model fitted values
  geom_line(aes(x = (syear*year_sd+mean(d.join$year)), y = bkt_est, color = "Model Estimate for MAMU Count")) + 
  
  # observed CBC MAMU counts
  geom_point(aes(x = (syear*year_sd+mean(d.join$year)), y = mamu.count, color = "Observed MAMU Count"), size = 0.8) + 
  
  # colors, legend, labels, axes, theme, etc.
  scale_color_manual(name = "Legend", 
                     breaks = c("Number of Observers", "Observed MAMU Count", "Model Estimate for MAMU Count"),
                     values = c("Number of Observers" = unname(bcs_colors["peach"]),
                                "Observed MAMU Count" = unname(bcs_colors["dark green"]), 
                                "Model Estimate for MAMU Count" = unname(bcs_colors["bright green"]))) +  
  scale_fill_manual(name = "", 
                    breaks = c("95% Confidence Interval"),
                    values = c("95% Confidence Interval" = unname(bcs_colors["dark green"]))) +
  
  # Add the second y-axis
  scale_y_continuous(
    name = "MAMU Count",
    sec.axis = sec_axis(~ . / scale_factor, name = "Number of Observers")
  ) +
  
  guides(color = guide_legend(order = 1), 
         fill = guide_legend(order = 2)) +
  
  labs(x = "Year",
       title = "Count of Marbled Murrelets",
       subtitle = "Christmas Bird Count in Seattle") +
  
  theme_bcs() + 
  
  theme(legend.spacing.y = unit(-0.65, "cm")) +
  
  guides(fill = guide_legend(keywidth = unit(1, "lines"),
                             keyheight = unit(0.6, "lines")))

# Export visualization
png("figures/mamu_cbc_counts_observers.png", height = 4, width = 6, units = "in", res = 300)
chart
dev.off()
