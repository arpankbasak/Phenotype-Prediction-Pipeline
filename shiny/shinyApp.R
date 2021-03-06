##Phenotype Prediction Pipeline shinyApp.R##

library(shiny)
library(shinydashboard)

sidebar <- dashboardSidebar(
  sidebarMenu(
    menuItem("Getting Started", tabName = "start", icon = icon("home")),
    menuItemOutput("dataDisplay"),
    menuItem("Predict Unknowns", tabName = "unknowns", icon = icon("magic"),
           badgeLabel = "new", badgeColor = "green"),
    menuItem("Cross Validation", tabName = "validation", icon = icon("line-chart"),
           badgeLabel = "new", badgeColor = "green"),
    menuItem("Clone via Github", icon = icon("github"), 
           href = "https://github.com/clabuzze/Phenotype-Prediction-Pipeline.git"),
    menuItem("Publication", icon = icon("flask"), href = NULL,
           badgeLabel = "coming soon", badgeColor = "blue"),
    fileInput(inputId = "data", label="1. Upload training dataset"),
    
    uiOutput("pheno1slider"),
    uiOutput("pheno2slider")
  )
)

body <- dashboardBody(
  tabItems(
    tabItem(tabName = "start",
            tags$div(
              HTML("<center><h2>Getting Started with MVP</h2></center>")
            ),
            actionButton("simulateData", "Simulate a dataset"),
            uiOutput("download")
            ),
    tabItem(tabName = "display",
            tags$div(
              HTML("<center><h2>Uploaded Data</h2></center>")
            ),
            dataTableOutput("dataTable")),
    tabItem(tabName = "unknowns",
            tags$div(
              HTML("<center><h2>Predict Phenotype of Unknown Sample</h2></center>")
            ),
            box(
              title = "Inputs", status = "warning", solidHeader = TRUE, width = NULL,
              column(width = 6,
                     strong("1. Upload training dataset via sidebar"), p(), strong("2. Select column of unknown sample"),
                     #fileInput(inputId = "testing", label="2. Upload testing dataset"),
                     uiOutput("unknown")
              ),
              column(width = 6,
                     textInput("pValue", label = "3. Input p value for differential expression", value = 0.05, placeholder = 0.05),
                     radioButtons("SelFil",label = "4. Select filtering method", choices = list("MVP", "None"), inline = TRUE, selected = "MVP"),
                     uiOutput("predict")
              )
            ),
            box(
              title = "Prediction", status = "warning", solidHeader = TRUE, width = NULL,
              textOutput("predRF"), br(),
              textOutput("predEN")
            )
    ),
    
    tabItem(tabName = "validation",
            tags$div(
              HTML("<center><h2>Cross Validate Machine Learning Methods</h2></center>")
            ),
            box(
              title = "Inputs", status = "warning", solidHeader = TRUE, width = NULL,
              column(width = 6,
                strong("1. Upload training dataset via sidebar"),p(),
                textInput("pValue", label = "2. Input p value for differential expression", value = 0.05, placeholder = 0.05)
              ),
              column(width = 6,
                radioButtons("SelFil", label = "3. Select filtering method", choices = list("MVP", "None"), inline = TRUE, selected = "MVP"),
                uiOutput("validation")
              )
            ),
            box(
              title = "Random Forest ROC Curve Analysis", status = "primary", solidHeader = TRUE,
              collapsible = TRUE, width = 6, collapsed = FALSE,
              plotOutput("rocRF.plot", height = 250), 
              textOutput("rocRF.mla"),
              textOutput("rocRF.roc")
            ),
            box(
              title = "Elastic Net ROC Curve Analysis", status = "primary", solidHeader = TRUE,
              collapsible = TRUE, width = 6, collapsed = FALSE,
              plotOutput("rocEN.plot", height = 250),
              textOutput("rocEN.mla"),
              textOutput("rocEN.roc")
            )
    )
  )
)


ui <- dashboardPage(
  dashboardHeader(title = "MVP Pipeline"), sidebar, body
)

server <- function(input, output) {
  
  fileRender <- observeEvent(input$data, {
    
    datatemp <- read.table(input$data$datapath)
      
    output$pheno1slider <- renderUI({
      #sliderInput("pheno1sliderIn", "Select columns of phenotype 1:", step = 1, ticks = FALSE, min=1, max=ncol(datatemp), value=c(1,(ncol(datatemp)/2)))
      checkboxGroupInput("pheno1checkIn", "Select columns of phenotype 1:", choices = c(1:ncol(datatemp)), inline = TRUE, selected = c(1:(ncol(datatemp)/2)))
    })
    
    output$pheno2slider <- renderUI({
      #sliderInput("pheno2sliderIn", "Select columns of phenotype 2:", step = 1, ticks = FALSE, min=1, max=ncol(datatemp), value=c(((ncol(datatemp)/2)+1),ncol(datatemp)))
      checkboxGroupInput("pheno2checkIn", "Select columns of phenotype 2:", choices = c(1:ncol(datatemp)), inline = TRUE, selected = c(((ncol(datatemp)/2)+1):ncol(datatemp)))
    })
    
    output$validation <- renderUI({
      actionButton("run.validate", "Run validation")
    })
    
    output$unknown <- renderUI({
      #checkboxGroupInput("unknownSampleIn", label=NULL, choices = c(1:ncol(datatemp)), inline = TRUE)
      radioButtons("unknownSampleIn", label=NULL, choices = c(1:ncol(datatemp)), inline = TRUE, selected = 1)
    })
    
    output$predict <- renderUI({
      actionButton("run.predictor", "Run prediction")
    })
    
    output$dataDisplay <- renderMenu({menuItem("Data Display", tabName = "display", icon = icon("database"),
                                              badgeLabel = "Look at me", badgeColor = "orange")})
    
    output$dataTable <- renderDataTable({datatemp}, options=list(scrollX=TRUE))
    
  })
  
  predictor <- observeEvent(input$run.predictor, {
    
   withProgress(message = 'Processing', value = 0, {
    
    tableIn <- read.table(input$data$datapath, header=T)
    
    expTable <- data.matrix(tableIn[,as.numeric(input$pheno1checkIn)])
    ctrlTable <- data.matrix(tableIn[,as.numeric(input$pheno2checkIn)])
    unknownSample <- data.matrix(tableIn[,as.numeric(input$unknownSampleIn)])
    
    p_value <- 0.05
    if(input$pValue != ""){
      p_value <- as.numeric(input$pValue)
    }
    
    exp <- data.matrix(expTable)
    ctrl <- data.matrix(ctrlTable)
    test <- data.matrix(unknownSample)
    
    genes <- c()
    labels <- c()
    predictionListElasticNet <- c()
    predictionListRandomForest <- c()
    predictionListSPLS <- c()
    total_features = 0
    quant = 0
    
    MVPq <- FALSE
    if(input$SelFil == "MVP"){
      MVPq <- TRUE
    }
    
    exp_test = data.matrix(exp)
    ctrl_test = data.matrix(ctrl)
    
    train_matrix = cbind(exp, ctrl)
    test_matrix = test
    row.names(test_matrix) <- row.names(train_matrix)
    
    complete_test <- cbind(train_matrix, test_matrix)
    train_matrix <- train_matrix[complete.cases(complete_test),]
    test_matrix <- test_matrix[complete.cases(complete_test),]
    test_matrix <- data.matrix(test_matrix)
    
    if(MVPq == TRUE){
      row_sub = apply(train_matrix, 1, function(row) (all(row != 0)))
      train_matrix <- train_matrix[row_sub,]
      test_matrix <- data.matrix(test_matrix[row_sub,])
      
      row_sub = apply(test_matrix,1, function(row) (all(row != 0)))
      train_matrix <- train_matrix[row_sub,]
      test_matrix <- data.matrix(test_matrix[row_sub,])
      
      quant = 0.9
    }
    
    train_matrix <- train_matrix * 100
    test_matrix <- test_matrix * 100
    train_matrix <- round(train_matrix,10)
    test_matrix <- round(test_matrix,10)
    
    incProgress(1/3, detail = paste("Doing part", 1, "of", 3))
    
    t_test <- data.matrix(apply(train_matrix,1,function(x){
      obj<-try(t.test(x[1:(ncol(exp))],x[(ncol(exp)+1):((ncol(exp))+(ncol(ctrl)))]), silent=TRUE)
      if (is(obj, "try-error")) return(NA)
      else return(obj$p.value)
    }))
    
    train_matrix <- data.matrix(train_matrix[t_test[,1] < p_value & !is.na(t_test[,1]),])
    test_matrix <- data.matrix(test_matrix[t_test[,1] < p_value & !is.na(t_test[,1]),])
    row.names(test_matrix) <- row.names(train_matrix)
    
    input <- cbind(train_matrix, test_matrix)
    
    returned <- apply(input,1,try(function(row){
      curve <- density(row[1:(ncol(exp))])
      data <- (c(mean(curve$x), var(curve$x)))
    }))
    
    returned2 <- apply(input,1,try(function(row){
      curve <- density(row[(ncol(exp)+1):((ncol(exp))+(ncol(ctrl)))])
      data <- (c(mean(curve$x), var(curve$x)))
    }))
    
    test_matrix <- t(test_matrix[abs(returned[1,] - returned2[1,])/(returned[2,] + returned2[2,])>quantile(abs(returned[1,] - returned2[1,])/(returned[2,] + returned2[2,]),quant),])
    train_matrix <- t(train_matrix[abs(returned[1,] - returned2[1,])/(returned[2,] + returned2[2,])>quantile(abs(returned[1,] - returned2[1,])/(returned[2,] + returned2[2,]),quant),]) 
    
    test_matrix <- test_matrix[,apply(train_matrix,2,var)>0.1e-50]
    train_matrix <- train_matrix[,apply(train_matrix,2,var)>0.1e-50]
    test_matrix <- t(data.matrix(test_matrix))
    
    incProgress(1/3, detail = paste("Doing part", 2, "of", 3))
    
    library(randomForest)
    library(pROC)
    library(stringr)
    
    phenotypes <- c(rep(0,ncol(exp)), rep(1,ncol(ctrl)))
    
    total_features = total_features + ncol(test_matrix)
    
    RandomForestCV <- randomForest(train_matrix, phenotypes)
    
    predictionRandomForest <- predict(RandomForestCV, test_matrix)
    
    predictionOutRF <- predictionRandomForest
    
    predictionOutRF
    
    incProgress(1/3, detail = paste("Doing part", 3, "of", 3))
    
    library(glmnet)
    library(pROC)
    library(stringr)
    
    ElasticNetCV <- cv.glmnet(train_matrix, phenotypes, nfolds=nrow(train_matrix), type.measure="deviance")
    
    predictionElasticNet <- predict(ElasticNetCV, test_matrix)
    
    predictionOutEN <- predictionElasticNet
      
    if(round(predictionOutRF) <= 0){
      predictionRF <- "Random Forest predicts this sample belongs to: Phenotype 1"
    }else{
      predictionRF <- "Random Forest predicts this sample belongs to: Phenotype 2"
    }
    
    if(round(predictionOutEN) <= 0){
      predictionEN <- "Elastic Net predicts this sample belongs to: Phenotype 1"
    }else{
      predictionEN <- "Elastic Net predicts this sample belongs to: Phenotype 2"
    }
  
    output$predRF <- renderText(predictionRF)
    output$predEN <- renderText(predictionEN)
   
   })   
   
  })
  
  validate <- observeEvent(input$run.validate, {
    
    tableIn <- read.table(input$data$datapath, header=T)
    
    expTable <- data.matrix(tableIn[,as.numeric(input$pheno1checkIn)])
    ctrlTable <- data.matrix(tableIn[,as.numeric(input$pheno2checkIn)])
    
    p_value <- 0.05
    if(input$pValue != ""){
      p_value <- as.numeric(input$pValue)
    }

    exp <- data.matrix(expTable)
    ctrl <- data.matrix(ctrlTable)
    
    genes <- c()
    labels <- c()
    predictionListElasticNet <- c()
    predictionListRandomForest <- c()
    predictionListSPLS <- c()
    total_features = 0
    quant = 0
    
    MVPq <- FALSE
    if(input$SelFil == "MVP"){
      MVPq <- TRUE
    }
    
    n <- 0
    
    withProgress(message = 'Making plot', value = 0, {
    
      for(i in 1:ncol(exp)){
        
        exp_minus_one = data.matrix(exp[,-i])
        exp_test = data.matrix(exp[,i])
        
        for(j in 1:ncol(ctrl)){
          
          n <- n + 1
          
          incProgress(1/(ncol(exp)*ncol(ctrl)), detail = paste("Doing part", n, "of", ncol(exp)*ncol(ctrl)))
          
          ctrl_minus_one = data.matrix(ctrl[,-j])
          ctrl_test = data.matrix(ctrl[,j])
          
          train_matrix = cbind(exp_minus_one, ctrl_minus_one)
          test_matrix = cbind(exp_test, ctrl_test)
          
          complete_test <- cbind(train_matrix, test_matrix)
          train_matrix <- train_matrix[complete.cases(complete_test),]
          test_matrix <- test_matrix[complete.cases(complete_test),]
          
          if(MVPq == TRUE){
            row_sub = apply(train_matrix, 1, function(row) (all(row != 0)))
            train_matrix <- train_matrix[row_sub,]
            test_matrix <- test_matrix[row_sub,]
            
            row_sub = data.matrix(apply(test_matrix, 1, function(row) (all(row != 0))))
            train_matrix <- train_matrix[row_sub,]
            test_matrix <- test_matrix[row_sub,]
            
            quant = 0.9
          }
          
          train_matrix <- train_matrix * 100
          test_matrix <- test_matrix * 100
          train_matrix <- round(train_matrix,10)
          test_matrix <- round(test_matrix,10)
          
          t_test <- data.matrix(apply(train_matrix,1,function(x){
            obj<-try(t.test(x[1:(ncol(exp)-1)],x[(ncol(exp)):((ncol(exp)-1)+(ncol(ctrl)-1))]), silent=TRUE)
            if (is(obj, "try-error")) return(NA)
            else return(obj$p.value)
          }))
          
          train_matrix <- data.matrix(train_matrix[t_test[,1] < p_value & !is.na(t_test[,1]),])
          test_matrix <- data.matrix(test_matrix[t_test[,1] < p_value & !is.na(t_test[,1]),])
          row.names(test_matrix) <- row.names(train_matrix)
          
          input <- cbind(train_matrix, test_matrix)
          
          returned <- apply(input,1,try(function(row){
            curve <- density(row[1:(ncol(exp)-1)])
            test1 <- (ncol(exp)-1)+(ncol(ctrl)-1)+1
            test2 <- (ncol(exp)-1)+(ncol(ctrl)-1)+2
            data <- (c(mean(curve$x), var(curve$x)))
          }))
          
          returned2 <- apply(input,1,try(function(row){
            curve <- density(row[(ncol(exp)):((ncol(exp)-1)+(ncol(ctrl)-1))])
            test1 <- (ncol(exp)-1)+(ncol(ctrl)-1)+1
            test2 <- (ncol(exp)-1)+(ncol(ctrl)-1)+2
            data <- (c(mean(curve$x), var(curve$x)))
          }))
          
          test_matrix <- t(test_matrix[abs(returned[1,] - returned2[1,])/(returned[2,] + returned2[2,])>quantile(abs(returned[1,] - returned2[1,])/(returned[2,] + returned2[2,]),quant),])
          train_matrix <- t(train_matrix[abs(returned[1,] - returned2[1,])/(returned[2,] + returned2[2,])>quantile(abs(returned[1,] - returned2[1,])/(returned[2,] + returned2[2,]),quant),]) 
          
          test_matrix <- test_matrix[,apply(train_matrix,2,var)>0.1e-50]
          train_matrix <- train_matrix[,apply(train_matrix,2,var)>0.1e-50]
          
          #heatmap(cbind(t(train_matrix), t(test_matrix)))
          
          library(randomForest)
          library(pROC)
          library(stringr)
          
          phenotypes <- c(rep(0,ncol(exp)-1), rep(1,ncol(ctrl)-1))
          
          total_features = total_features + ncol(test_matrix)
          
          RandomForestCV <- randomForest(train_matrix, phenotypes)
          
          predictionRandomForest <- predict(RandomForestCV, test_matrix)
          
          predictionListRandomForest <- c(predictionListRandomForest, predictionRandomForest)
          
          labels <- c(labels, 0, 1)
          
          library(glmnet)
          library(pROC)
          library(stringr)
          
          ElasticNetCV <- cv.glmnet(train_matrix, phenotypes, nfolds=nrow(train_matrix), type.measure="deviance")
          
          predictionElasticNet <- predict(ElasticNetCV, test_matrix)
          
          predictionListElasticNet <- c(predictionListElasticNet, predictionElasticNet)
          
        }
        
      }
      
    })
    
      rocRF <- roc(labels, predictionListRandomForest, plot=FALSE)
      output$rocRF.plot <- renderPlot({plot.roc(rocRF)})
      output$rocRF.mla <- renderText("Random Forest")
      output$rocRF.roc <- renderPrint(rocRF$auc)
      
      rocEN <- roc(labels, predictionListElasticNet, plot=FALSE)
      output$rocEN.plot <- renderPlot({plot.roc(rocEN)})
      output$rocEN.mla <- renderText("Elastic Net")
      output$rocEN.roc <- renderPrint(rocEN$auc)
    
  })
  
  simulate <- observeEvent(input$simulateData, {
    
    library(optBiomarker)
    
    simulated <- simData(nTrain = 20, nBiom = 1000)
    
    datatemp <- data.matrix(t(data.matrix(simulated$data)))
    
    output$download <- renderUI(downloadButton('downloadData', 'Download'))
    
    output$downloadData <- downloadHandler(
      filename = function() { paste("simulated", '.txt', sep='') },
      content = function(file) {
        write.table(datatemp, file, sep="\t")
      }
    )
    
  })
  
}

shinyApp(ui, server)