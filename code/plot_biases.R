#-----------------------------------------------------------------------------#
#-----------------------------------------------------------------------------#

# list of required packages
packages = c("terra","plyr","spatstat","ggplot2","extrafont",
             "tidyterra","geiger","cowplot","Matching","png","cowplot")

# load packages (install if missing in the system)
for (p in packages) {
  if (length(find.package(p, quiet=T)) == 0) install.packages(p)
  require(p, character.only=T, quietly=T)
}

loadfonts(quiet=T)

# target resolution of raster variables (in m)
pixel_res = 10000

#-----------------------------------------------------------------------------#
# load required data
#-----------------------------------------------------------------------------#

# original data with the location of flood events
ids = read.csv("flash_flood_reports.csv", stringsAsFactors=F)

# vector file with per-country flood risk estimates (0-100)
flood_risk = vect("NRI_Shapefile_Counties/NRI_Shapefile_Counties.shp")

# vector with continental USA (used to plot the location of the study site)
continental_usa = vect("continental_usa.shp")

#-----------------------------------------------------------------------------#
# transform data into needed formats and projections
#-----------------------------------------------------------------------------#

# create vector from flood event coordinates
flood_events = vect(ids, geom=c("lsrLon","lsrLat"), crs="EPSG:4326", keepgeom=T)

# reproject flood event vector into the same projection as the flood risk map
# (Note: done in this direction to reduce computation time)
flood_events = project(flood_events, crs(flood_risk))

# reproject the shapefile of the continental USA
continental_usa = project(continental_usa, crs(flood_risk))

# build shapefile with the extent of the study site
study_site = vect(ext(flood_events), crs=crs(flood_risk))

#-----------------------------------------------------------------------------#
# create flood risk raster (resolution defined set in the configuration file)
#-----------------------------------------------------------------------------#

# create a reference raster to populate
reference = rast(extend(ext(flood_events), pixel_res),
                 res=pixel_res, crs=crs(flood_risk))

# rasterize flood risk data
flood_risk = crop(flood_risk, extend(ext(flood_events), pixel_res))
risk_map = rasterize(flood_risk, reference, field="RISK_SCORE")

#-----------------------------------------------------------------------------#
# build plots mapping flood events and flood risks
#-----------------------------------------------------------------------------#

# colors used to map the flood risk
cr = colorRampPalette(c('#f0f9e8','#bae4bc','#7bccc4','#43a2ca','#0868ac'))

# map the frequency of flood events per pixel in the reference raster
# (NOTE: done to minimize information loss when events are clustered)
event_frequency = vect(cbind(

  # count number of flood events per pixel
  ddply(
    data.frame(pos=cellFromXY(risk_map, geom(flood_events)[,c("x","y")])),
    .(pos), summarise, count=length(pos)),

  # extract coordinates of unique pixels with flood events
  as.data.frame(xyFromCell(risk_map, cell_id$pos))

), geom=c("x","y"), crs=crs(risk_map))

# classify frequencies of flood events (to simplify the legend)
event_frequency$count_class = ""
event_frequency$count_class[which(event_frequency$count < 10)] = "< 10"
event_frequency$count_class[which(event_frequency$count %in% 10:20)] = "10-20"
event_frequency$count_class[which(event_frequency$count > 10)] = "> 20"
event_frequency$count_class = factor(event_frequency$count_class,
                                     levels=c("< 10", "10-20", "> 20"))

# map of study site location
p = ggplot() + theme_bw(base_size=7, base_family="Helvetica") +
  geom_spatvector(data=continental_usa) +
  geom_spatvector(data=study_site, fill=NA, show.legend=NA, linewidth=2) +
  theme(axis.text=element_blank(), axis.ticks=element_blank(),
        panel.border=element_blank(), panel.grid=element_blank(),
        plot.margin = unit(c(0, 0, 0, 0), "points"))

# save plot (intermediate output)
ggsave("study_site.png", p, dpi=150, units="mm")

# plot flood risk map over study site
p = ggplot() + theme_bw(base_size=7, base_family="Helvetica") +
  geom_spatraster(data=risk_map, aes(fill=RISK_SCORE)) +
  geom_spatvector(data=event_frequency, aes(size=count_class),
                  show.legend=NA, alpha=0.2, linewidth=NA) +
  scale_fill_gradientn(colours=cr(5), limits=c(0,100), na.value=NA) +
  labs(fill="Flood risk", size="Number of events") +
  theme(axis.text=element_blank(),
        axis.ticks=element_blank(),
        panel.border=element_blank(),
        panel.grid=element_blank(),
        legend.position=c(1.10,0.35))

p = ggdraw(p) + draw_image(readPNG('study_site.png'),
                             scale=0.2, vjust=-0.3, hjust=-0.3)

# save plot on the flood risk per county
ggsave("Figure_1_flood_risk.png", p,
       width=180, height=100,
       dpi=300, units="mm")

#-----------------------------------------------------------------------------#
# build plots comparing the distribution of
# regional flood risks and its sampled distribution
#-----------------------------------------------------------------------------#

# extract flood risk for sampling locations
flood_event_risk = extract(risk_map, flood_events, ID=F)[[1]]

# build Empirical Cummulative Distribution
# Function (ECDF) for study site and samples
cdf0 = ecdf(flood_risk$RISK_SCORE) # baseline
cdf1 = ewcdf(flood_event_risk) # sampled

# apply ECDF's to a common range of flood risk (0-100)
ks0 = data.frame(x=0:100, y=cdf0(0:100), group="Study site")
ks1 = data.frame(x=0:100, y=cdf1(0:100), group="Observed")

# estimate the difference between the study site and sampled distributions
# (NOTE: Used to map the difference between the distribution lines)
difference = data.frame(a=ks0$y, b=ks1$y)
difference = data.frame(x=0:100,
                        min=apply(difference, 1, min),
                        max=apply(difference, 1, max))

# use Komolgorov-Smirnov test to compare distributions
ks_test = ks.boot(flood_risk$RISK_SCORE, flood_event_risk, nboots=1000)
effect_size = sprintf("%0.2f", ks_test$ks$statistic[[1]])
p_value = sprintf("%0.2f", ks_test$ks$p.value[[1]])
ks_test = paste0("\nEffect size: ", format(effect_size, digits=2),
                 "\nP-value: < ", format(p_value, digits=2))

# plot comparigon of distributions
p1 = ggplot() +
  theme_bw(base_family="Helvetica", base_size=6) +
  geom_ribbon(data=difference, aes(x=x, ymin=min, ymax=max),
              fill="red", alpha=0.1, colour=NA) +
  geom_line(data=ks0, aes(x=x, y=y), col="black", size=0.15) +
  geom_line(data=ks1, aes(x=x, y=y), col="red",
            size=0.15, linetype="longdash") +
  labs(x="Flood risk", y="Cumulitive Distibution") +
  coord_cartesian(xlim=c(0,100), ylim=c(0,1)) +
  scale_x_continuous(expand=c(0,0)) +
  scale_y_continuous(expand=c(0,0)) +
  annotate('text', label=ks_test, x=-Inf,
           y=Inf, hjust=-0.1, vjust=1.5,
           family="Helvetica", size=3) +
  theme(panel.background=element_blank(),
        panel.border=element_blank(),
        panel.grid=element_blank(),
        legend.position="none",
        axis.line.x=element_line(colour="#464646", size=0.2),
        axis.line.y=element_line(colour="#464646", size=0.2))

# plot regional histogram
p2 = ggplot(data.frame(x=flood_risk$RISK_SCORE), aes(x=x)) +
  theme_bw(base_family="Helvetica", base_size=6) +
  geom_histogram(binwidth=5, fill="grey80",
                 aes(y=..count../sum(..count..)*100)) +
  scale_x_continuous(expand=c(0,0)) +
  scale_y_continuous(expand=c(0,0)) +
  labs(x="Flood Risk", y="Frequency of counties (%)") +
  coord_cartesian(xlim=c(0,100), ylim=c(0,15)) +
  theme(panel.background=element_blank(),
        panel.border=element_blank(),
        panel.grid=element_blank(),
        legend.position="none",
        axis.line.x=element_line(colour="#464646", size=0.2),
        axis.line.y=element_line(colour="#464646", size=0.2))

# combine plots
p = plot_grid(p1, p2, ncol=2, labels=c("a)", "b)"),
              align='hv', label_size=8, label_fontface="bold",
              rel_widths=c(0.5, 0.5))

# save plot with comparison of distributions
ggsave("Figure_2_distribution_comparison.png", p,
       width=180, height=80, dpi=300, units="mm")

#-----------------------------------------------------------------------------#
# combine and export plots
#-----------------------------------------------------------------------------#

# Manually define the layout
layout_matrix <- rbind(c(1, 2),
                       c(1, 3))

# Arrange the plots
grid.arrange(p1, p0, p3, layout_matrix=layout_matrix, widths=c(3,1))

ggsave("flood_risk_bias.png", p, width=30, height=30, units="mm", dpi=400)

