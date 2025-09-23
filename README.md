# 🚁 Zomato Drone Delivery Analytics

## 📋 Project Overview

This project analyzes the feasibility and cost optimization of implementing drone delivery for Zomato's food delivery service. The analysis includes comprehensive database modeling, cost analysis, and location-based delivery optimization.

## 🎯 Key Features

### 📊 Database Schema
- **Customers & Restaurants**: Location-based data with GPS coordinates
- **Orders**: Complete order management with timing and weather data
- **Drone Specifications**: Technical specs including payload, range, and battery capacity
- **Cost Analysis**: Detailed cost comparison between drone and traditional delivery

### 🔍 Analytics Components
1. **Feasibility Analysis**: Determines which orders can be delivered by drones
2. **Cost Optimization**: Compares drone vs rider delivery costs
3. **Location Intelligence**: Local zone management and delivery area optimization
4. **Weather Impact**: Analysis of weather conditions on delivery feasibility
5. **Performance Metrics**: Comprehensive reporting and insights

## 🗂️ Project Structure

```
Zomato-drone-delivery/
├── zomato.sql                  # Main database schema and analysis queries
├── connect_mysql.py           # MySQL connection and data export script
├── export_instructions.md     # Manual export guide from MySQL Workbench
└── README.md                  # This file
```

## 🚀 Key Analysis Results

### Delivery Feasibility
- **Conservative Estimate**: Orders definitely deliverable by weakest drone
- **Realistic Estimate**: Orders deliverable by average drone capabilities
- **Optimistic Estimate**: Orders deliverable by best drone in fleet

### Cost Optimization
- Detailed cost comparison between drone and rider delivery
- Break-even analysis and profit calculations
- Distance-based pricing strategies
- Weather-dependent delivery decisions

### Location Intelligence
- Local delivery zones with drone flight permissions
- Restricted areas (airports, military zones)
- Zone-to-zone delivery route optimization
- Distance categorization and analysis

## 🛠️ Setup Instructions

### Prerequisites
- MySQL Server 8.0+
- MySQL Workbench (optional)
- Python 3.7+ (for data export script)

### Database Setup
1. **Create Database**:
   ```sql
   CREATE DATABASE zomato_drone;
   USE zomato_drone;
   ```

2. **Run the Schema**:
   Execute the `zomato.sql` file in your MySQL environment

3. **Load Data**:
   - Place your CSV files in MySQL's secure file directory
   - Update file paths in the LOAD DATA INFILE statements
   - Run the data loading queries

### Python Setup (Optional)
```bash
pip install mysql-connector-python pandas
```

Update MySQL credentials in `connect_mysql.py` and run:
```bash
python connect_mysql.py
```

## 📈 Key Metrics Analyzed

### Operational Metrics
- Average delivery distance: Calculated using Haversine formula
- Delivery time estimation: Based on drone speed and traffic patterns
- Weather impact: Analysis of delivery feasibility under different conditions
- Payload optimization: Weight-based delivery decisions

### Financial Metrics
- Cost per delivery (drone vs rider)
- Break-even analysis
- Profit margins by distance category
- ROI calculations for drone fleet investment

### Geographic Analysis
- Delivery zone optimization
- Distance-based service areas
- Location-based pricing strategies
- Zone-to-zone delivery patterns

## 🔧 Technical Features

### Database Functions
- **Haversine Distance Calculation**: Accurate distance between GPS coordinates
- **Zone Detection**: Automatic drone delivery zone eligibility
- **Cost Calculation**: Dynamic pricing based on multiple factors

### Analysis Views
- **order_enriched**: Enhanced order data with calculated metrics
- **order_feasibility**: Drone delivery feasibility assessment
- **cost_analysis**: Comprehensive cost comparison
- **local_orders_summary**: Location-based delivery insights

## 📊 Sample Queries

### Feasibility Analysis
```sql
SELECT 
    COUNT(*) as total_orders,
    SUM(realistic_feasible) as drone_deliverable,
    ROUND(SUM(realistic_feasible) * 100.0 / COUNT(*), 2) as feasibility_rate
FROM order_feasibility;
```

### Cost Savings Analysis
```sql
SELECT 
    AVG(rider_cost_inr - drone_cost_inr) as avg_savings_per_order,
    SUM(rider_cost_inr - drone_cost_inr) as total_potential_savings
FROM cost_analysis 
WHERE is_drone_feasible = 1;
```

### Zone Performance
```sql
SELECT 
    zone_name,
    COUNT(*) as orders,
    SUM(location_eligible_for_drone) as drone_eligible
FROM local_orders_summary
GROUP BY zone_name;
```

## 🎯 Business Insights

### Delivery Optimization
- **Short Distance Orders** (0-2km): High drone feasibility, maximum cost savings
- **Medium Distance Orders** (2-5km): Moderate feasibility, good profit margins
- **Long Distance Orders** (5km+): Limited feasibility, rider delivery preferred

### Weather Considerations
- Clear weather: 100% drone operation capability
- Light rain: Reduced operation with weather-resistant drones
- Heavy rain/storms: Rider delivery only

### Zone-Based Strategy
- **Commercial Zones**: High order density, optimal for drone hubs
- **Residential Areas**: Scattered delivery points, mixed delivery approach
- **Restricted Zones**: No-fly areas requiring alternative routing

## 🚀 Future Enhancements

- Real-time weather API integration
- Dynamic pricing based on demand
- Machine learning for delivery time prediction
- Route optimization algorithms
- Customer preference analysis
- Fleet management optimization

## 👨‍💻 Author

**Ansh Pal**
- GitHub: [@anshpal3924](https://github.com/anshpal3924)
- Project: [Zomato Drone Delivery Analytics](https://github.com/anshpal3924/Zomato-drone-delivery)

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

---

*This project demonstrates advanced SQL analytics, geospatial analysis, and business intelligence applied to modern delivery logistics challenges.*