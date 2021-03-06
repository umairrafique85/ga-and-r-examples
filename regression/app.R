# Load the necessary libraries. 
library(shiny)
library(googleAuthR)       # For authentication
library(googleAnalyticsR)  # How we actually get the Google Analytics data

gar_set_client(web_json = "ga-web-client.json",
               scopes = "https://www.googleapis.com/auth/analytics.readonly")
options(googleAuthR.redirect = "https://gilligan.shinyapps.io/regression/")

library(tidyverse)         # Includes dplyr, ggplot2, and others; very key!
library(knitr)             # Nicer looking tables
library(plotly)            # We're going to make the charts interactive
library(DT)                # Interactive tables
library(scales)            # Useful for some number formatting in the visualizations
library(MASS)              # For stepwise regression

# Define the base theme for visualizations
theme_base <- theme_light() +
  theme(panel.grid = element_blank(),
        panel.border = element_blank(),
        axis.ticks = element_blank(),
        axis.line = element_line(colour = "gray70"),
        strip.background = element_rect(fill = "white", color = NA),
        strip.text = element_text(colour = "gray20", face = "bold"))

## ui.R
ui <- fluidPage(title = "Regression with Day of Week",
                tags$head(includeScript("gtm.js")),
                tags$h2("Regression with Day of Week*"),
                tags$div(paste("Select a Google Analytics view and date range and then pull the data. From there, explore",
                               "a regression of a categorical/nominal variable -- day of week -- to see to what extent the",
                               "day of the week is predictive of traffic to the site.")),
                tags$br(),
                sidebarLayout(
                  sidebarPanel(tags$h4("Select Base Data Parameters"),
                               # Account/Property/View Selection
                               authDropdownUI("auth_menu",
                                              inColumns = FALSE),
                               # Date Range Selection
                               dateRangeInput("date_selection", 
                                              label = "Select date range:",
                                              start = Sys.Date()-90,
                                              end = Sys.Date()-1),
                               # Whether or not to enable anti-sampling
                               checkboxInput("anti_sampling",
                                             label = "Include anti-sampling (slows down app a bit).",
                                             value = TRUE),
                               # Action button. We want the user to control when the
                               # underlying call to Google Analytics occurs.
                               tags$div(style="text-align: center",
                                        actionButton("query_data", "Get/Refresh Data!", 
                                                     style="color: #fff; background-color: #337ab7; border-color: #2e6da4")),
                               tags$br(),
                               tags$hr(),
                               tags$h4("Choose a Dummy!"),
                               tags$div("It doesn't (really) matter what you choose for the dummy. The results of the",
                                        "model will be (almost) the same (although the coefficients will change!),",
                                        "and the model summary statistics will change (but just a little bit):"),
                               tags$br(),
                               selectInput("dummy_select",
                                           label=NA,
                                           choices = c("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"),
                                           selected = "SAT")),
                  mainPanel(tabsetPanel(type = "tabs",
                                        tabPanel("Base Data",
                                                 tags$br(),
                                                 tags$div(paste("This is the base data and a visualization of the data",
                                                                "that you queried. It should look pretty familiar!")),
                                                 tags$br(),
                                                 plotlyOutput("base_data_plot", height = "400px"),
                                                 tags$br(),
                                                 dataTableOutput("base_data_table")),
                                        tabPanel("Boxplot",
                                                 tags$br(),
                                                 tags$div(paste("Maybe this looks a little different than how you normally",
                                                                "think of this data? It's grouping the data by day of week",
                                                                "and showing the median and quartiles of the number of sessions",
                                                                "recorded for each day.")),
                                                 tags$br(),
                                                 plotOutput("box_plot", height = "400px")),
                                        tabPanel("Dummies!",
                                                 tags$br(),
                                                 tags$div(paste("This is the exact same data, except columns have been added",
                                                                "for six of seven weekdays with a 1 or 0 assigned based on whether",
                                                                "that date is that weekday (we don't need a seventh column,",
                                                                "because the seventh day is already implicit -- when all six day",
                                                                "columns are all 0s.")),
                                                 tags$br(),
                                                 dataTableOutput("data_dummies_table")),
                                        tabPanel("Stepwise Summary",
                                                 tags$br(),
                                                 tags$div(paste("This is the raw summary of a stepwise regression model using",
                                                                "the data set on the 'Dummies' tab. It's not super pretty, is it?")),
                                                 tags$br(),
                                                 verbatimTextOutput("model_summary")),
                                        tabPanel("Plain English",
                                                 tags$br(),
                                                 tags$div(paste("This is a somewhat easier on the eyes way of interpreting the",
                                                                "summary of the model.")),
                                                 tags$br(),
                                                 tags$b(textOutput("p_value")),
                                                 tags$br(),
                                                 tags$b(textOutput("adj_r_sq")),
                                                 tags$br(),
                                                 tags$div("We can represent the model as an equation that looks like this:"),
                                                 uiOutput("model_equation"),
                                                 tags$div("Or, we can look at a table with the intercept and coefficients for each value:"),
                                                 dataTableOutput("ind_vars")),
                                        tabPanel("Visualization",
                                                 tags$br(),
                                                 tags$div(paste("Let's bring it all together and look at a visualization that shows the",
                                                                "actual values and the predicted values:")),
                                                 tags$br(),
                                                 plotlyOutput("final_plot", height = "400px"),
                                                 tags$br(),
                                                 tags$div(paste("If you want to try plugging in the numbers yourself, here is the equation:")),
                                                 uiOutput("model_equation_2"),
                                                 tags$br(),
                                                 tags$div(paste("If you're wondering how you multiply a number by weekday, hopefully the table",
                                                                "below makes that clear (most of the coefficients get multiplied by 0, but",
                                                                "one gets multiplied by 1!")),
                                                 tags$br(),
                                                 tags$div(paste("And here is the original data (with dummy variables) with the actual and",
                                                                "predicted values:")),
                                                 tags$br(),
                                                 dataTableOutput("predict_vs_actual")
                                        )))),
                tags$hr(),
                tags$div("*This app is part of a larger set of apps that demonstrate some uses of R in conjunction",
                         "with Google Analytics (and Twitter). For the code for this app, as well as an R Notebook",
                         "that includes more details, see:", tags$a(href = "https://github.com/SDITools/ga-and-r-examples/",
                                                                    "https://github.com/SDITools/ga-and-r-examples/"),"."),
                tags$br()
)

## server.R
server <- function(input, output, session){
  
  # Create a non-reactive access token
  gar_shiny_auth(session)
  
  # Populate the Account/Property/View dropdowns and return whatever the
  # selected view ID is
  view_id <- callModule(authDropdown, "auth_menu", ga.table = ga_account_list)
  
  # Reactive function to pull the data.
  get_ga_data <- reactive({
    
    # Only pull the data if the "Get Data" button is clicked
    input$query_data
    
    # Pull the data. Go ahead and shorten the weeday names
    isolate(google_analytics(viewId = view_id(),
                             date_range = input$date_selection,
                             metrics = "sessions",
                             dimensions = c("date", "dayOfWeekName"),
                             anti_sample = input$anti_sampling) %>% 
              mutate(weekday = substring(dayOfWeekName, 1, 3)) %>% 
              mutate(weekday = toupper(weekday)) %>% 
              mutate(weekday = factor(weekday,
                                      levels = c("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"))) %>% 
              dplyr::select(date, weekday, sessions))
  })
  
  # Reactive function to create the dummy variables
  get_dummies <- reactive({
    
    # Get the base data
    ga_data <- get_ga_data()
    
    # Set the list of days to include by *dropping* the selected dummy value
    wdays <- c("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT")
    include_cols <- wdays[!wdays %in% input$dummy_select]
    include_cols <- c("date", include_cols, "sessions")
    
    # Get the data set up where each day of the week has its own column. That means one of the 
    # columns will be a "1" and the rest will be "0s" for each date
    ga_data_dummies <- ga_data %>% 
      mutate(var = 1) %>%                                          # Put a 1 in all rows of a column
      spread(key = weekday, value = var, fill = 0) %>%             # Create the dummy variables
      dplyr::select(one_of(include_cols))         # Re-order and drop the selected weekday
  })
  
  # Get the stepwise model
  get_step_model <- reactive({
    
    # Get the data and drop the date column
    analysis_data <- get_dummies() %>% dplyr::select(-date)
    
    # Fit the full model
    full_model <- lm(sessions ~., data = analysis_data)
    
    # Now, see if stepwise can knock some things out (it shouldn't in this case,
    # but it doesn't hurt to try)
    step_model <- stepAIC(full_model, direction = "both", trace = FALSE)
  })
  
  # Get the model summary. We're going to use this quite a bit
  get_model_summary <- reactive({
    step_model <- get_step_model()
    model_summary <- summary(step_model)
  })
  
  # Get the intercept and coefficients in a data frame
  get_ind_vars <- reactive({
    
    # Get model summary
    model_summary <- get_model_summary()
    
    # Make a data frame with just the coefficients and their confidence levels. This is converting
    # the p-values to confidence levels
    ind_vars <- model_summary$coefficients %>% as.data.frame() %>%
      mutate(Variable = rownames(.)) %>%
      mutate(`Confidence Level` = ifelse(`Pr(>|t|)` < 0.01, "99%",
                                         ifelse(`Pr(>|t|)` < 0.05, "95%",
                                                ifelse(`Pr(>|t|)` < 0.1, "90%",
                                                       ifelse(`Pr(>|t|)` < 0.2, "80%","<80%"))))) %>%
      dplyr::select(Variable, Coefficient = Estimate, `Confidence Level`)
  })
  
  # Create the model equation. We display it in two spots, so we have to make two outputs.
  # So... normally this isn't something that would have it's own reactive function, but it makes sense.
  get_model_equation <- reactive({
    
    # Get coefficients and intercept
    ind_vars <- get_ind_vars()
    
    # Generate a string that introduces MathJax equation notation so that we have values that
    # can be pasted together and output as RMarkdown. This gets a little screwy, but it's
    # just so we can output a "normal" looking equation.
    model_equation <- ind_vars %>%
      mutate(rmd = ifelse(Variable == "(Intercept)", round(Coefficient),
                          paste0(round(Coefficient), " \\times ", Variable)))
    
    # Collapse that into the equation string
    model_equation <- model_equation$rmd %>%
      paste(collapse = " + ") %>%
      paste0("$$Sessions = ", ., "$$") %>% 
      gsub("\\+\\ \\-", "\\-", .)
  })
  
  ## Outputs
  
  # Output the base data table
  output$base_data_table <- renderDataTable({
    get_ga_data() %>% 
      datatable(colnames = c("Date", "Day of Week", "Sessions"),  rownames = FALSE)
  })
  
  # Output the base data plot
  output$base_data_plot <- renderPlotly({
    
    # Get the data to plot
    ga_data <- get_ga_data()
    
    # Build the plot
    gg <- ggplot(ga_data, aes(x = date, y = sessions)) + 
      geom_line(color = "#00a2b1") +
      scale_y_continuous(expand = c(0,0), limits=c(0, max(ga_data$sessions)*1.05), label = comma) +
      labs(title = "Sessions by Day",
           x = "Date") +
      theme_base
    
    ggplotly(gg) %>% layout(autosize=TRUE)
  })
  
  # Output the boxplot
  output$box_plot <- renderPlot({
    
    # Get the data to plot
    ga_data <- get_ga_data()
    
    # Make a boxplot where we combine all of the data points for each day of week together
    ggplot(ga_data, aes(x = weekday, y = sessions)) + 
      geom_boxplot(fill = "gray90", color = "gray40", outlier.colour = "#00a2b1") +
      scale_y_continuous(expand = c(0,0), limits=c(0, max(ga_data$sessions)*1.05), label = comma) +
      labs(title = "Sessions Variation by Day of Week", y = "Sessions") +
      theme_base +
      theme(plot.title = element_text(size = 18, hjust = 0.5, face = "bold"),
            axis.ticks = element_blank(),
            axis.title.x = element_blank(),
            axis.title.y = element_text(size = 14, face = "bold"),
            axis.line.x = element_line(colour="gray20"),
            axis.text = element_text(size = 14))
  })
  
  # Output the data with dummy variables
  output$data_dummies_table <- renderDataTable({
    get_dummies() %>% 
      datatable(rownames = FALSE)
  })
  
  # Output the results of a stepwise regression
  output$model_summary <- renderPrint({
    
    # Get the model summary
    model_summary <- get_model_summary()
    
    # Output that summary
    print(model_summary)
  })
  
  # Output the p-value and interpretation
  output$p_value <- renderText({
    
    # Get the model summary
    model_summary <- get_model_summary()
    
    # Get the F-statistic
    f_statistic <- model_summary$fstatistic
    
    # Get the p_value
    p_value <- pf(f_statistic[1], f_statistic[2], f_statistic[3],lower.tail=F)
    attributes(p_value) <- NULL
    
    # Format it to be more readable
    p_value <- format(round(p_value,4), nsmall = 4)
    
    # Determine the confidence level
    confidence <- ifelse(p_value < 0.01, "99%",
                         ifelse(p_value < 0.05, "95%",
                                ifelse(p_value < 0.1, "90%",
                                       ifelse(p_value < 0.2, "80%","<80%"))))
    
    # Build the statement
    confidence <- ifelse(confidence == "<80%", "not statistically significant.",
                         paste("statistically significant at a", confidence,"confidence level."))
    
    result <- paste0("The model has a p-value of ", p_value, ", which means it is ", confidence)
    
  })
  
  # Output the Adjusted R-Squared
  output$adj_r_sq <- renderText({
    
    # Get the model summary
    model_summary <- get_model_summary()
    
    # Get the adjusted R-squared
    adj_r_sq <- model_summary$adj.r.squared
    
    result <- paste0("The model has an adjusted R-squared of ", format(adj_r_sq, digits = 3, nsmall=2),
                     ", which means that ", format(adj_r_sq*100, digits = 3, nsmall=0), 
                     "% of the variation in sessions is explained by the model.")
  })
  
  # Output the equation. See: http://shiny.rstudio.com/gallery/mathjax.html
  output$model_equation <- renderUI({
    model_equation <- get_model_equation()
    # Output the equation
    withMathJax(helpText(model_equation))
  })
  
  # We need a second version of the same equqtion...
  output$model_equation_2 <- renderUI({
    model_equation <- get_model_equation()
    # Output the equation
    withMathJax(helpText(model_equation))
  })
  
  # Output the table of coefficients
  output$ind_vars <- renderDataTable({
    
    # Get the coefficients table
    ind_vars <- get_ind_vars()
    
    # Round the coefficients
    ind_vars <- ind_vars %>% 
      mutate(Coefficient = round(Coefficient))
    
    # Get the intercept and coefficients
    datatable(ind_vars, rownames = FALSE, options = list(dom="t"))
  })
  
  # Output a plot showing the actual vs. predictions
  output$final_plot <- renderPlotly({
    
    step_model <- get_step_model()
    ga_data_dummies <- get_dummies()
    ind_vars <- get_ind_vars()
    
    # Predict the results using the data -- to get a visualization of the results (basically, 
    # visualizing the residuals). This is just a vector of  predicted sessions.
    predict_vs_actual <- predict(step_model, ga_data_dummies)
    
    # Get just the intercept (for a horizontal line we'll add)
    y_intercept <- ind_vars %>% filter(Variable == "(Intercept)") %>% 
      dplyr::select(Coefficient) %>% as.numeric()
    
    # Add those predictions to a data frame that shows the actuals. We'll hold onto
    # this so we can preview it in the output. 
    predict_vs_actual_df <- ga_data_dummies %>% 
      cbind(data.frame(`Predicted Sessions` = predict_vs_actual)) 
    
    # Add that y-intercept as a constant to the data to be plotted. geom_hline()
    # would be better for this, but I gave up fighting to get the legend I was
    # wanting, so hacking around it this way
    predict_vs_actual_df <- predict_vs_actual_df %>% 
      mutate(Intercept = y_intercept)
    
    # Rename "Sessions" to "Actual Sessions" for clarity
    names(predict_vs_actual_df) <- gsub("sessions", "Actual Sessions", names(predict_vs_actual_df)) %>% 
      gsub("Predicted.Sessions", "Predicted Sessions", .)
    
    # For cleaner plotting, convert that to a tidy format and then turn it into a ggplot
    predict_vs_actual_for_plot <- predict_vs_actual_df %>% 
      dplyr::select(Date = date, `Actual Sessions`, `Predicted Sessions`, Intercept) %>% 
      gather(key = metric, value = value, -Date) %>% 
      # Total hack to add better spacing in the legend
      mutate(metric = paste0(metric, "    "))
    
    
    # Get the max value so we can expand the limits
    y_lim <- max(predict_vs_actual_for_plot$value) * 1.1
    
    # Plot the actuals vs. predicted. Ideally, this would show up FIRST, but it comes out second
    gg_predict_vs_actual <- ggplot(data = predict_vs_actual_for_plot,
                                   mapping = aes(x = Date, y = value, color = metric, linetype = metric)) +
      geom_line(size = 0.5) +
      scale_color_manual(values=c("#00a2b1", "gray50", "#ed1c24")) +
      scale_linetype_manual(name = "limit", values = c("solid", "dashed", "dotted")) +
      scale_y_continuous(expand = c(0,0), limits = c(0,y_lim), label=number_format(accuracy=1, big.mark=",")) +
      labs(x = "Date", y = "Sessions", title = "Sessions by Day: Actual vs. Predicted") +
      theme_base 
    
    # Output the (interactive) chart
    ggplotly(gg_predict_vs_actual) %>% layout(legend = list(orientation = "h", 
                                                            x=0.5, xanchor="center",
                                                            y=1.05, yanchor="top"))
    
  })
  
  
  
  # Output the table with dummy variables and actual vs. predicted
  output$predict_vs_actual <- renderDataTable({
    
    step_model <- get_step_model()
    ga_data_dummies <- get_dummies()
    
    # Predict the results using the data -- to get a visualization of the results (basically, 
    # visualizing the residuals). This is just a vector of  predicted sessions.
    predict_vs_actual <- predict(step_model, ga_data_dummies)
    
    # Add those predictions to a data frame that shows the actuals. We'll hold onto
    # this so we can preview it in the output. 
    predict_vs_actual_df <- ga_data_dummies %>% 
      cbind(data.frame(`Predicted Sessions` = predict_vs_actual)) %>% 
      mutate(`Predicted.Sessions` = round(`Predicted.Sessions`))
    
    # Rename "Sessions" to "Actual Sessions" for clarity
    names(predict_vs_actual_df) <- gsub("sessions", "Actual Sessions", names(predict_vs_actual_df)) %>% 
      gsub("Predicted.Sessions", "Predicted Sessions", .)
    
    # Return the data frame
    predict_vs_actual_df %>% 
      datatable(rownames = FALSE)
  })
  
}

# shinyApp(gar_shiny_ui(ui, login_ui = gar_shiny_login_ui), server)
shinyApp(gar_shiny_ui(ui, login_ui = silent_auth), server)