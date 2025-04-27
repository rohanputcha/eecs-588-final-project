from flask import Flask, request, jsonify
import os
import json

app = Flask(__name__)

# -------------------------
# Flask endpoint definition
# -------------------------
@app.route('/flask-api/clear', methods=['DELETE'])
def clear():
    output_dir = 'output'
    if os.path.exists(output_dir):
        try:
            for filename in os.listdir(output_dir):
                file_path = os.path.join(output_dir, filename)
                if os.path.isfile(file_path) or os.path.islink(file_path):
                    os.unlink(file_path)
            return jsonify({"message": "Output directory cleared"}), 200
        except Exception as e:
            return jsonify({"error": f"Error clearing output directory: {str(e)}"}), 500
    else:
        return jsonify({"message": "Output directory does not exist"}), 200

@app.route('/flask-api/device-data', methods=['POST'])
def store_device_data():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Missing JSON data"}), 400

        output_file = "device_data.jsonl"
        with open(output_file, "a") as f:
            f.write(f"{json.dumps(data)}\n")

        return jsonify({"message": "Device data stored successfully"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == '__main__':
    app.run(debug=True, port=9000)
