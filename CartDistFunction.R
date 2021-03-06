#A function to convert a dataframe (as a .csv file) of coordinates to Cartesian coordinates.
#Calculates least-cost distances among sites in water. 
#Then plots a map of points, a linear model of least-cost geographic vs Cartesian distances, and adds Cartesian coordinates to your input file.
#If any sites are too close to land it will stop, as it requires depths <0 metres. 

coord_cartesian<-function(coordinates,min.depth,max.depth,trans=NA,gridres,directory){
  
  #gridres = resolution (mins) of the bathymetric grid used for least coast path (default = 2)
  ##Coordinates file must have column names Lat and Long, and column 1 should be your pop names or codes
  
  require(gdistance)
  require(ggplot2)
 
  coords<-read.csv(coordinates,header=T)
  
  if (length(colnames(coords))<3){
    stop("You need at least 3 columns in your dataframe: Populations, Long, and Lat")
  }
  
  
  ## Set map limits------adding and subtracting 2 degrees to make the lc.dists function work better
  Lat.lim=c(min(coords$Lat)-2,max(coords$Lat)+2)
  Long.lim=c(min(coords$Long)-2,max(coords$Long)+2)
  
  #Get the bathydata and keep it
  setwd(directory)
  writeLines("Getting bathymetry data from NOAA database\n")
  bathydata<-marmap::getNOAA.bathy(lon1 = Long.lim[1], lon2 = Long.lim[2], lat1 = Lat.lim[1], lat2 = Lat.lim[2],
                           resolution = 1,keep=TRUE)
  
  #Make colours and plot it
  blues <- c("lightsteelblue4", "lightsteelblue3",
             "lightsteelblue2", "lightsteelblue1")
  greys <- c(grey(0.6), grey(0.93), grey(0.99))
  
  #Get depths and plot. If any depths > 0 we will not proceed
  depths<-marmap::get.depth(bathydata,x=coords$Long,y=coords$Lat,locator=F)
  
  #colours to assign those locations which are in water "green" and on land "red". 
  depths$col <- "green"
  depths[depths$depth>=0,"col"] <- "red"
  
  
  pdf("MyMap.pdf")
  
      marmap::plot.bathy(bathydata,image = TRUE, land = T, lwd = 0.03,
                         bpal = list(c(0, max(bathydata), greys),
                                     c(min(bathydata), 0, blues)),deep=0,shallow=0)
      
      marmap::plot.bathy(bathydata, lwd = 1, deep = 0, shallow = 0, step = 0, add = TRUE)
      
      legend("bottomright",
             legend = c("Water","Land"), 
             col=c("green","red"),
             pch=19,
             pt.cex=1.5,
             bg="white")
      
      points(depths$lon, depths$lat,pch=19,cex=2,col=depths$col)
  
  dev.off()

  
  if(sum(depths$depth >= 0)>0){
      stop("\nSome of your points appear to be too close to land. Suggest moving points farther off land for this analysis\n\n\n")
    }
  
  #if all points are in water then continue
  writeLines("\nAll coordinates appear to be in water.\n")
  
  writeLines("\nCalculating transition object for least-cost analysis.\n")
  
  #Make the trans mat object then do the lc dist calculation
  
  if(is.na(trans)){
  trans <- marmap::trans.mat(bathydata,min.depth = min.depth,max.depth = max.depth) 
  }
  
  sites<-coords[,c("Long","Lat")]
  rownames(sites)<-coords[,1]
  
  writeLines("Calculating least cost distances. This will probably can take a few minutes depending onresolution...")
  lc.dists <- marmap::lc.dist(trans, 
                      sites, 
                      res="dist")
  writeLines("Meta MDS scaling into Cartesian coordinates\n\n")
  #Now the cartesian conversion using metaMDS
  set.seed(1)
  cart.dists <- as.data.frame(metaMDS(lc.dists,k=2)$points) #K=2 because we want 2 dimensions
  set.seed(1)
  stress.values <- vegan::metaMDS(lc.dists,k=2)$stress # this will vary slightly each time.
  dist.cart.dists <- dist(cart.dists)
  
  if(stress.values>0.05){
    print(paste0("Potentially high stress (>0.05) value detected in metaMDS reprojection: ",round(stress.values,4)))}else{print(paste0("metaMDS reprojection stress = ",round(stress.values,4)))}
  
  cartfit <- cbind(matrix(lc.dists)[,1],matrix(dist.cart.dists)[,1])
  cartfit <- data.frame(cartfit)
  colnames(cartfit) <- c("Deg","Cart")
  cartfit$Stress <- stress.values
  
  p1<-ggplot(filter(cartfit,Deg>0,Cart>0),aes(x=Deg,y=Cart))+
    geom_point()+
    scale_x_log10()+
    scale_y_log10()+
    stat_smooth(method="lm")+
    annotation_logticks(sides="bl")+
    theme_bw()+
    labs(x="Geographic distance",y="Cartesian distance")
  
  ggsave(filename =paste0(directory,"Cartesian_vs_Geographic_Distances.png"),p1,device = "png",width = 8, height=8,dpi = 400)
  ggsave(filename = paste0(directory,"Cartesian_vs_Geographic_Distances.pdf"),p1,device = "pdf",width = 8, height=8,dpi = 400)
  
  mod <- lm(log10(Deg)~log10(Cart),data=filter(cartfit,Cart>0,Deg>0))

  output <- list(Coords <- cbind(coords,cart.dists), #Geographic and Cartesian coordinates
                 fitplot <- p1, #fitted plot
                 mod <- mod, #fitted model
                 trans <- trans, #transition object
                 lc.dist <- lc.dist, #least cost distance matrix
                 bathydata <- bathydata) #bathymetric layer
  
  return(output)
  
  writeLines(paste0("Writing coordinates to file ",directory,"MyCartesianCoordinates.csv"))
  
  write.csv(x = Coords,file = paste0(directory,"MyCartesianCoordinates.csv"),quote = FALSE,row.names = F)
  
}