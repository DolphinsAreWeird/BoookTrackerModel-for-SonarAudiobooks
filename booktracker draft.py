from ultralytics import YOLO
import cv2
import math
import pygame
from gtts import gTTS
import io
import time
import threading

# Initialize pygame mixer for audio
pygame.mixer.init()

# Start webcam
cap = cv2.VideoCapture(0)  # Use 0 for the default webcam
cap.set(cv2.CAP_PROP_BUFFERSIZE, 2)  # Reduce buffer size to avoid lag
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)  # Set frame width
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)  # Set frame height

# Load YOLO model
model = YOLO("yolo-Weights/yolov8n.pt")

# TTS Function using threading
def speak(text):
    def play_audio():
        tts = gTTS(text, lang="th")
        fp = io.BytesIO()
        tts.write_to_fp(fp)
        fp.seek(0)
        pygame.mixer.music.load(fp)
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy():
            pygame.time.Clock().tick(10)

    threading.Thread(target=play_audio).start()

# Parameters for control
frame_skip = 10  # Increased skip to reduce computation
frame_count = 0
last_instruction_time = time.time()
instruction_cooldown = 3
current_state = None
last_detection_time = time.time()
no_detection_threshold = 2

confidence_threshold = 0.3  # Increased for faster filtering

width_coverage = 0.65
height_coverage = 0.85

def draw_optimal_box(img):
    height, width = img.shape[:2]
    
    optimal_width = int(width * width_coverage)
    optimal_height = int(height * height_coverage)
    
    x1 = (width - optimal_width) // 2
    y1 = (height - optimal_height) // 2
    x2 = x1 + optimal_width
    y2 = y1 + optimal_height
    
    cv2.rectangle(img, (x1, y1), (x2, y2), (0, 255, 0), 2)
    
    center_x, center_y = width // 2, height // 2
    marker_size = 20
    cv2.line(img, (center_x - marker_size, center_y), (center_x + marker_size, center_y), (0, 255, 0), 1)
    cv2.line(img, (center_x, center_y - marker_size), (center_x, center_y + marker_size), (0, 255, 0), 1)
    
    return (x1, y1, x2, y2)

while True:
    success, img = cap.read()
    if not success:
        print("Failed to read from the webcam.")
        break

    # Resize frame to reduce computation
    img = cv2.resize(img, (640, 480))

    frame_height, frame_width, _ = img.shape
    frame_center_x, frame_center_y = frame_width // 2, frame_height // 2
    
    optimal_box = draw_optimal_box(img)
    opt_x1, opt_y1, opt_x2, opt_y2 = optimal_box
    
    optimal_width = opt_x2 - opt_x1
    optimal_height = opt_y2 - opt_y1

    min_box_size = int(optimal_width * 0.7)
    max_box_size = int(optimal_width * 1.3)
    dynamic_offset_threshold_x = int(frame_width * 0.04)
    dynamic_offset_threshold_y = int(frame_height * 0.04)

    book_detected = False
    if frame_count % frame_skip == 0:  # Skip frames for faster processing
        results = model(img, stream=True)
        for r in results:
            boxes = r.boxes
            for box in boxes:
                if int(box.cls[0]) == 73 and box.conf[0] >= confidence_threshold:
                    book_detected = True
                    last_detection_time = time.time()
                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    book_center_x = (x1 + x2) // 2
                    book_center_y = (y1 + y2) // 2
                    
                    cv2.rectangle(img, (x1, y1), (x2, y2), (255, 0, 255), 2)
                    cv2.circle(img, (book_center_x, book_center_y), 5, (0, 0, 255), -1)

                    offset_x = book_center_x - frame_center_x
                    offset_y = book_center_y - frame_center_y
                    box_width = x2 - x1
                    box_height = y2 - y1
                    
                    if box_width < min_box_size or box_height < optimal_height * 0.7:
                        new_state = "closer"
                    elif box_width > max_box_size or box_height > optimal_height * 1.3:
                        new_state = "further"
                    elif abs(offset_x) > dynamic_offset_threshold_x:
                        new_state = "left" if offset_x > 0 else "right"
                    elif abs(offset_y) > dynamic_offset_threshold_y:
                        new_state = "down" if offset_y > 0 else "up"
                    else:
                        new_state = "perfect"

                    current_time = time.time()
                    if new_state != current_state and current_time - last_instruction_time >= instruction_cooldown:
                        instructions = {
                            "perfect": "สมบูรณ์แบบ, perfect",
                            "left": "เลื่อนซ้าย, left",
                            "right": "เลื่อนขวา, right",
                            "up": "เลื่อนขึ้น, up",
                            "down": "เลื่อนลง, down",
                            "closer": "เข้าใกล้มากขึ้น, closer",
                            "further": "ถอยออกไป, further"
                        }
                        speak(instructions[new_state])
                        current_state = new_state
                        last_instruction_time = current_time

                    confidence = math.ceil((box.conf[0] * 100)) / 100
                    cv2.putText(img, f"Conf: {confidence:.2f}", (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 0, 0), 2)
                    cv2.putText(img, f"State: {new_state}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)

        # Shorter no detection warning
        if not book_detected and time.time() - last_detection_time > no_detection_threshold:
            current_time = time.time()
            if current_time - last_instruction_time >= instruction_cooldown:
                speak("ไม่เห็นหนังสือ, no book")
                last_instruction_time = current_time

    frame_count += 1
    cv2.imshow('Book Detection', img)
    if cv2.waitKey(1) == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
pygame.mixer.quit()
